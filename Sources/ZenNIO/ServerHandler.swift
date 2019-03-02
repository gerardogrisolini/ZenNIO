//
//  HTTPHandler.swift
//  ZenNIO
//
//  Created by Gerardo Grisolini on 28/02/2019.
//

import NIO
import NIOHTTP1

private func httpResponseHead(request: HTTPRequestHead, status: HTTPResponseStatus, headers: HTTPHeaders = HTTPHeaders()) -> HTTPResponseHead {
    var head = HTTPResponseHead(version: request.version, status: status, headers: headers)
    let connectionHeaders: [String] = head.headers[canonicalForm: "connection"].map { $0.lowercased() }
    
    if !connectionHeaders.contains("keep-alive") && !connectionHeaders.contains("close") {
        // the user hasn't pre-set either 'keep-alive' or 'close', so we might need to add headers
        
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
    }
    return head
}

final class ServerHandler: ChannelInboundHandler {
    
    public typealias InboundIn = HTTPServerRequestPart
    public typealias OutboundOut = HTTPServerResponsePart
    
    private enum State {
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
        
        mutating func responseComplete() {
            precondition(self == .sendingResponse, "Invalid state for response complete: \(self)")
            self = .idle
        }
    }
    
    private var buffer: ByteBuffer! = nil
    private var keepAlive = false
    private var state = State.idle
    private let htdocsPath: String
    
    private var savedBodyBytes: [UInt8] = []
    private var infoSavedRequestHead: HTTPRequestHead?
    private var infoSavedBodyBytes: Int = 0
    
    private var continuousCount: Int = 0
    
    private var handler: ((ChannelHandlerContext, HTTPServerRequestPart) -> Void)?
    private var handlerFuture: EventLoopFuture<Void>?
    private let fileIO: NonBlockingFileIO?
    
    public init(fileIO: NonBlockingFileIO?, htdocsPath: String) {
        self.htdocsPath = htdocsPath
        self.fileIO = fileIO
    }
    
    private func completeResponse(_ context: ChannelHandlerContext, trailers: HTTPHeaders?, promise: EventLoopPromise<Void>?) {
        self.state.responseComplete()
        
        let promise = self.keepAlive ? promise : (promise ?? context.eventLoop.makePromise())
        if !self.keepAlive {
            promise!.futureResult.whenComplete { (_: Result<Void, Error>) in context.close(promise: nil) }
        }
        self.handler = nil
        
        context.writeAndFlush(self.wrapOutboundOut(.end(trailers)), promise: promise)
    }
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
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
            savedBodyBytes.removeAll()
            let route = ZenNIO.getRoute(request: &request)
            if route != nil && route?.handler == nil {
                fileRequest(ctx: context, request: infoSavedRequestHead!)
                return
            }
            
            request.clientIp = context.channel.remoteAddress!.description
            request.eventLoop = context.eventLoop
            processRequest(request: request, route: route)
                .whenSuccess { response in
                    self.processResponse(ctx: context, response: response)
            }
        }
    }
    
    private func processCORS(_ request: HttpRequest, _ response: HttpResponse) -> Bool {
        response.headers.add(name: "Access-Control-Allow-Origin", value: "*")
        response.headers.add(name: "Access-Control-Allow-Headers", value: "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range")
        response.headers.add(name: "Access-Control-Allow-Methods", value: "OPTIONS, POST, PUT, GET, DELETE")
        if request.head.method == .OPTIONS {
            response.headers.add(name: "Access-Control-Max-Age", value: "86400")
            response.headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
            response.completed(.noContent)
            return true;
        } else {
            response.headers.add(name: "Access-Control-Expose-Headers", value: "Content-Length,Content-Range")
            return false;
        }
    }
    
    private func processSession(_ request: HttpRequest, _ response: HttpResponse, _ filter: Bool) -> Bool {
        var session = ZenNIO.sessions.get(authorization: request.authorization, cookies: request.cookies)
        if session == nil {
            session = ZenNIO.sessions.new()
            if request.referer.isEmpty {
                ZenNIO.sessions.set(session: session!)
                response.addHeader(.setCookie, value: "sessionId=\(session!.id); expires=Thu, 01 Jan 2050 00:00:00 UTC; path=/;")
            }
        }
        request.setSession(session!)
        return filter && !request.isAuthenticated
    }
    
    private func processRequest(request: HttpRequest, route: Route?) -> EventLoopFuture<HttpResponse> {
        let promise = request.eventLoop.makePromise(of: HttpResponse.self)
        //        request.eventLoop.execute {
        let response = HttpResponse(promise: promise)
        if ZenNIO.cors, processCORS(request, response) {
            response.completed(.noContent)
        } else if let route = route {
            if ZenNIO.session, processSession(request, response, route.filter) {
                response.completed(.unauthorized)
            } else {
                request.parseRequest()
                route.handler!(request, response)
            }
        } else {
            response.completed(.notFound)
        }
        //        }
        return promise.futureResult
    }
    
    private func processResponse(ctx: ChannelHandlerContext, response: HttpResponse) {
        let head = self.httpResponseHead(request: self.infoSavedRequestHead!, status: response.status, headers: response.headers)
        ctx.write(self.wrapOutboundOut(HTTPServerResponsePart.head(head)), promise: nil)
        if let body = response.body {
            self.buffer = ctx.channel.allocator.buffer(capacity: body.count)
            self.buffer.writeBytes(body)
            ctx.write(self.wrapOutboundOut(.body(.byteBuffer(self.buffer))), promise: nil)
        }
        self.completeResponse(ctx, trailers: nil, promise: nil)
    }
    
    //    private func processResponse(ctx: ChannelHandlerContext, response: HttpResponse) {
    //        ctx.channel.getOption(option: HTTP2StreamChannelOptions.streamID).then { (streamID) -> EventLoopFuture<Void> in
    //            var head = HTTPResponseHead(version: .init(major: 2, minor: 0), status: response.status, headers: response.headers)
    //            head.headers.add(name: "x-stream-id", value: String(streamID.networkStreamID!))
    //            ctx.write(self.wrapOutboundOut(HTTPServerResponsePart.head(head)), promise: nil)
    //            if let body = response.body {
    //                self.buffer = ctx.channel.allocator.buffer(capacity: body.count)
    //                self.buffer.write(bytes: body)
    //                ctx.write(self.wrapOutboundOut(.body(.byteBuffer(self.buffer))), promise: nil)
    //            }
    //            return ctx.channel.writeAndFlush(self.wrapOutboundOut(HTTPServerResponsePart.end(nil)))
    //        }.whenComplete {
    //            ctx.close(promise: nil)
    //        }
    //    }
    
    fileprivate func fileRequest(ctx: ChannelHandlerContext, request: (HTTPRequestHead)) {
        let path = self.htdocsPath + request.uri
        let fileHandleAndRegion = self.fileIO!.openFile(path: path, eventLoop: ctx.eventLoop)
        fileHandleAndRegion.whenFailure {
            switch $0 {
            case let e as IOError where e.errnoCode == ENOENT:
                print("IOError (not found)")
            case let e as IOError:
                print("IOError (other)")
            default:
                print("\($0): \(type(of: $0)) error")
            }
        }
        fileHandleAndRegion.whenSuccess { (file, region) in
            var responseStarted = false
            let response = responseHead(request: request, fileRegion: region, contentType: path.contentType)
            return self.fileIO!.readChunked(fileRegion: region,
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
        
        func responseHead(request: HTTPRequestHead, fileRegion region: FileRegion, contentType: String) -> HTTPResponseHead {
            var response = httpResponseHead(request: request, status: .ok)
            response.headers.add(name: "Content-Length", value: "\(region.endIndex)")
            response.headers.add(name: "Content-Type", value: contentType)
            return response
        }
    }
    
    fileprivate func httpResponseHead(request: HTTPRequestHead, status: HTTPResponseStatus, headers: HTTPHeaders = HTTPHeaders()) -> HTTPResponseHead {
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

    func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }
    
    func handlerAdded(context: ChannelHandlerContext) {
        self.buffer = context.channel.allocator.buffer(capacity: 0)
    }
    
    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
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
}
