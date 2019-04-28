//
//  ServerHandler.swift
//  ZenNIO
//
//  Created by Gerardo Grisolini on 28/02/2019.
//

import Foundation
import NIO
import NIOHTTP1
import CNIOExtrasZlib

public enum State {
    case idle
    case waitingForRequestBody
    case sendingResponse
    
    mutating func requestReceived() {
        precondition(self == .idle, "Invalid state for request received: \(self)")
        self = .waitingForRequestBody
    }
    
    mutating func requestComplete() {
        precondition(self == .waitingForRequestBody, "Invalid state for request complete: \(self)")
        self = .sendingResponse
    }
    
    public mutating func responseComplete() {
        precondition(self == .sendingResponse, "Invalid state for response complete: \(self)")
        self = .idle
    }
}

open class ServerHandler: ChannelInboundHandler {
    public typealias InboundIn = HTTPServerRequestPart
    public typealias OutboundOut = HTTPServerResponsePart
    
    public var keepAlive = false
    public var state = State.idle
    private let htdocsPath: String
    
    private var savedBodyBytes: [UInt8] = []
    public var infoSavedRequestHead: HTTPRequestHead?
    private var handler: ((ChannelHandlerContext, HTTPServerRequestPart) -> Void)?
//    private let fileIO: NonBlockingFileIO?
    
//    public init(fileIO: NonBlockingFileIO?, htdocsPath: String) {
//        self.htdocsPath = htdocsPath
//        self.fileIO = fileIO
//    }
    public init(htdocsPath: String) {
        self.htdocsPath = htdocsPath
    }

    private func completeResponse(_ context: ChannelHandlerContext, trailers: HTTPHeaders?, promise: EventLoopPromise<Void>?) {
        self.state.responseComplete()
        
        let promise = self.keepAlive ? promise : (promise ?? context.eventLoop.makePromise())
        if !self.keepAlive {
            promise!.futureResult.whenComplete { (_: Result<Void, Error>) in context.close(promise: nil) }
        }
        context.writeAndFlush(self.wrapOutboundOut(.end(trailers)), promise: promise)
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let reqPart = self.unwrapInboundIn(data)
        switch reqPart {
        case .head(let request):
            self.infoSavedRequestHead = request
            self.keepAlive = request.isKeepAlive
            self.state.requestReceived()
        case .body(buffer: let buf):
            self.savedBodyBytes.append(contentsOf: buf.getBytes(at: 0, length: buf.readableBytes)!)
        case .end:
            self.state.requestComplete()
            
            var request = HttpRequest(head: infoSavedRequestHead!, body: savedBodyBytes)
            request.clientIp = context.channel.remoteAddress!.description
            request.eventLoop = context.eventLoop
            //savedBodyBytes.removeAll()
            
            let httpResponse: EventLoopFuture<HttpResponse>
            if let route = ZenNIO.router.getRoute(request: &request) {
                httpResponse = processRequest(ctx: context, request: request, route: route)
            } else {
                httpResponse = processFileRequest(ctx: context, request: request)
            }
            httpResponse.whenSuccess { response in
                self.processResponse(ctx: context, response: response)
            }
        }
    }
    
    private func processCORS(_ request: HttpRequest, _ response: HttpResponse) {
        guard ZenNIO.cors else { return }
        
        response.headers.add(name: "Access-Control-Allow-Origin", value: "*")
        response.headers.add(name: "Access-Control-Allow-Headers", value: "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range,Authorization")
        response.headers.add(name: "Access-Control-Allow-Methods", value: "OPTIONS, POST, PUT, GET, DELETE")
        response.headers.add(name: "Access-Control-Expose-Headers", value: "Content-Length,Content-Range")
    }
    
    private func processSession(_ request: HttpRequest, _ response: HttpResponse, _ filter: Bool) -> Bool {
        var session = ZenNIO.sessions.get(authorization: request.authorization, cookies: request.cookies)
        if session == nil {
            session = ZenNIO.sessions.new(id: request.clientIp, token: nil)
            if request.referer.isEmpty {
                ZenNIO.sessions.set(session: session!)
                response.addHeader(.setCookie, value: "sessionId=\(session!.id); expires=Thu, 01 Jan 2050 00:00:00 UTC; path=/;")
            }
        }
        request.setSession(session!)
        if filter {
            return request.isAuthenticated
        }
        return true
    }
    
    private func processRequest(ctx: ChannelHandlerContext, request: HttpRequest, route: Route) -> EventLoopFuture<HttpResponse> {
        let promise = request.eventLoop.makePromise(of: HttpResponse.self)
        request.eventLoop.execute {
            let response = HttpResponse(body: ctx.channel.allocator.buffer(capacity: 0), promise: promise)
            if ZenNIO.session && !self.processSession(request, response, route.filter) {
                response.completed(.unauthorized)
            } else {
                self.processCORS(request, response)
                request.parseRequest()
                route.handler(request, response)
                if let session = request.session {
                    ZenNIO.sessions.set(session: session)
                }
            }
        }
        return promise.futureResult
    }
    
    private func processFileRequest(ctx: ChannelHandlerContext, request: HttpRequest) -> EventLoopFuture<HttpResponse> {
        let promise = request.eventLoop.makePromise(of: HttpResponse.self)
        request.eventLoop.execute {
            let response = HttpResponse(body: ctx.channel.allocator.buffer(capacity: 0), promise: promise)
            
            var path = self.htdocsPath + request.url
            if let index = path.firstIndex(of: "?") {
                path = path[path.startIndex...path.index(before: index)].description
            }
            
            if let data = FileManager.default.contents(atPath: path) {
                response.addHeader(.contentType, value: path.contentType)
                response.send(data: data)
                response.completed()
            } else {
                response.completed(.notFound)
            }
        }
        return promise.futureResult
    }

    open func processResponse(ctx: ChannelHandlerContext, response: HttpResponse) {
        let head = self.httpResponseHead(request: self.infoSavedRequestHead!, status: response.status, headers: response.headers)
        ctx.write(self.wrapOutboundOut(.head(head)), promise: nil)

        let lenght = 32 * 1024
        let count = response.body.readableBytes
        var index = 0
        while index < count {
            let end = index + lenght > count ? count - index : lenght
            if let bytes = response.body.getSlice(at: index, length: end) {
                ctx.write(self.wrapOutboundOut(.body(.byteBuffer(bytes))), promise: nil)
            }
            index += end
        }
        self.state.responseComplete()

        self.completeResponse(ctx, trailers: nil, promise: nil)
    }
    
    private func httpResponseHead(request: HTTPRequestHead, status: HTTPResponseStatus, headers: HTTPHeaders = HTTPHeaders()) -> HTTPResponseHead {
        var head = HTTPResponseHead(version: request.version, status: status, headers: headers)
        switch (request.isKeepAlive, request.version.major, request.version.minor) {
        case (true, 1, 0):
            // HTTP/1.0 and the request has 'Connection: keep-alive', we should mirror that
            head.headers.add(name: "Connection", value: "keep-alive")
        case (false, 1, let n) where n >= 1:
            // HTTP/1.1 (or treated as such) and the request has 'Connection: close', we should mirror that
            head.headers.add(name: "Connection", value: "close")
        default:
            // we should match the default or are dealing with some HTTP that we don't support, let's leave as is
            ()
        }
        return head
    }
    
    public func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }
    
    public func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        switch event {
        case let evt as ChannelEvent where evt == ChannelEvent.inputClosed:
            // The remote peer half-closed the channel. At this time, any
            // outstanding response will now get the channel closed, and
            // if we are idle or waiting for a request body to finish we
            // will close the channel immediately.
            switch self.state {
            case .idle, .waitingForRequestBody:
                context.close(promise: nil)
            case .sendingResponse:
                self.keepAlive = false
            }
        default:
            context.fireUserInboundEventTriggered(event)
        }
    }
    
    /*
    open func fileRequest(ctx: ChannelHandlerContext, request: (HTTPRequestHead)) {
        func errorResponse(_ status: HTTPResponseStatus) {
            let response = self.httpResponseHead(request: request, status: status)
            ctx.write(self.wrapOutboundOut(.head(response)), promise: nil)
            self.completeResponse(ctx, trailers: nil, promise: nil)
        }
     
        guard let fileIO = self.fileIO else {
            errorResponse(.notFound)
            return
        }

        var path = self.htdocsPath + request.uri
        if let index = path.firstIndex(of: "?") {
            path = path[path.startIndex...path.index(before: index)].description
        }

        let fileHandleAndRegion = fileIO.openFile(path: path, eventLoop: ctx.eventLoop)
        fileHandleAndRegion.whenFailure {
            let status: HTTPResponseStatus
            switch $0 {
            case let e as IOError where e.errnoCode == ENOENT:
                print("IOError (file not found): \(path)")
                status = .notFound
            case let e as IOError:
                print("IOError (other): \(e.reason) - \(e.description)")
                status = .internalServerError
            default:
                print("\($0): \(type(of: $0)) error")
                status = .badRequest
            }
            errorResponse(status)
        }
        fileHandleAndRegion.whenSuccess { (file, region) in
            var responseStarted = false
            let response = self.responseHead(request: request, fileRegion: region, contentType: path.contentType)
            return fileIO.readChunked(fileRegion: region,
                                      chunkSize: 32 * 1024,
                                      allocator: ctx.channel.allocator,
                                      eventLoop: ctx.eventLoop) { buffer in
                if !responseStarted {
                    responseStarted = true
                    ctx.write(self.wrapOutboundOut(.head(response)), promise: nil)
                }
                return ctx.writeAndFlush(self.wrapOutboundOut(.body(.byteBuffer(buffer))))
            }.flatMap { () -> EventLoopFuture<Void> in
                let p = ctx.eventLoop.makePromise(of: Void.self)
                self.completeResponse(ctx, trailers: nil, promise: p)
                return p.futureResult
            }.flatMapError { error in
                if !responseStarted {
                    let response = self.httpResponseHead(request: request, status: .ok)
                    ctx.write(self.wrapOutboundOut(.head(response)), promise: nil)
                    var buffer = ctx.channel.allocator.buffer(capacity: 100)
                    buffer.writeString("fail: \(error)")
                    ctx.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                    self.state.responseComplete()
                    return ctx.writeAndFlush(self.wrapOutboundOut(.end(nil)))
                } else {
                    return ctx.close()
                }
            }.whenComplete { (_: Result<Void, Error>) in
                _ = try? file.close()
            }
        }
    }
    
    open func responseHead(request: HTTPRequestHead, fileRegion region: FileRegion, contentType: String) -> HTTPResponseHead {
        var response = httpResponseHead(request: request, status: .ok)
        response.headers.add(name: "Content-Length", value: "\(region.endIndex)")
        response.headers.add(name: "Content-Type", value: contentType)
        return response
    }
    */
}
