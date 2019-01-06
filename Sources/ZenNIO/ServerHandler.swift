//
//  ServerHandler.swift
//  ZenNIO
//
//  Created by admin on 20/12/2018.
//

import NIO
import NIOHTTP1
import NIOHTTP2

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
    private var savedBodyBytes: [UInt8] = []
    private var keepAlive = false
    private var state = State.idle
    private let htdocsPath: String
    
    private var infoSavedRequestHead: HTTPRequestHead?
    private var handler: ((ChannelHandlerContext, HTTPServerRequestPart) -> Void)?
    private var handlerFuture: EventLoopFuture<Void>?
    private let fileIO: NonBlockingFileIO
    
    public init(fileIO: NonBlockingFileIO, htdocsPath: String, http: HttpProtocol = .v1) {
        self.htdocsPath = htdocsPath
        self.fileIO = fileIO
    }
    
    func dynamicHandler(ctx: ChannelHandlerContext, request: HTTPServerRequestPart) {
        switch request {
        case .head(let request):
            self.infoSavedRequestHead = request
            self.keepAlive = request.isKeepAlive
            self.state.requestReceived()
        case .body(buffer: let buf):
            self.savedBodyBytes.append(contentsOf: buf.getBytes(at: 0, length: buf.readableBytes)!)
        case .end:
            self.state.requestComplete()
            
            //            let response = HttpResponse()
            //            response.send(text: "Hello World!")
            //            response.completed()
            
            processRequest(ctx: ctx).whenSuccess({ response in
                self.processResponse(ctx: ctx, response: response)
            })
        }
    }
    
    private func processRequest(ctx: ChannelHandlerContext) -> EventLoopFuture<HttpResponse> {
        let promise = ctx.eventLoop.newPromise(of: HttpResponse.self)
        ctx.eventLoop.execute {
            
            let response = HttpResponse(promise: promise)
            var request = HttpRequest(head: self.infoSavedRequestHead!, body: self.savedBodyBytes)
            if request.head.method == .OPTIONS {
                
                response.headers.add(name: "Access-Control-Allow-Origin", value: "*")
                response.headers.add(name: "Access-Control-Allow-Headers", value: "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range")
                response.headers.add(name: "Access-Control-Allow-Methods", value: "OPTIONS, POST, PUT, GET, DELETE")
                response.headers.add(name: "Access-Control-Max-Age", value: "86400")
                response.headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
                response.completed(.noContent)
                
            } else if let route = ZenNIO.getRoute(request: &request) {
                
                if ZenNIO.cors {
                    response.headers.add(name: "Access-Control-Allow-Origin", value: "*")
                    response.headers.add(name: "Access-Control-Allow-Headers", value: "DNT,User-Agent,X-Requested-With,If-Modified-Since,Cache-Control,Content-Type,Range")
                    response.headers.add(name: "Access-Control-Allow-Methods", value: "OPTIONS, POST, PUT, GET, DELETE")
                    response.headers.add(name: "Access-Control-Expose-Headers", value: "Content-Length,Content-Range")
                }
                
                var session = ZenNIO.sessions.get(authorization: request.authorization, cookies: request.cookies)
                if session == nil {
                    session = ZenNIO.sessions.new()
                    if request.referer.isEmpty {
                        ZenNIO.sessions.set(session: session!)
                        response.addHeader(.setCookie, value: "sessionId=\(session!.id); expires=Thu, 01 Jan 2050 00:00:00 UTC; path=/;")
                    }
                }
                session!.ip = ctx.channel.remoteAddress!.description
                session!.eventLoop = ctx.eventLoop
                request.setSession(session!)
                
                if route.secure && !request.isAuthenticated {
                    response.completed(.unauthorized)
                } else {
                    request.parseRequest()
                    route.handler(request, response)
                }
                
            } else {
                response.completed(.notFound)
            }
        }
        
        return promise.futureResult
    }
    
    private func processResponse(ctx: ChannelHandlerContext, response: HttpResponse) {
        let head = self.httpResponseHead(request: self.infoSavedRequestHead!, status: response.status, headers: response.headers)
        ctx.write(self.wrapOutboundOut(HTTPServerResponsePart.head(head)), promise: nil)
        if let body = response.body {
            self.buffer = ctx.channel.allocator.buffer(capacity: body.count)
            self.buffer.write(bytes: body)
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
    
    private func handleFile(ctx: ChannelHandlerContext, request: HTTPServerRequestPart, path: String) {
        if var buffer = self.buffer {
            buffer.clear()
        }
        
        func sendErrorResponse(request: HTTPRequestHead, _ error: Error) {
            var body = ctx.channel.allocator.buffer(capacity: 128)
            let response = { () -> HTTPResponseHead in
                switch error {
                case let e as IOError where e.errnoCode == ENOENT:
                    body.write(staticString: "IOError (not found)\r\n")
                    return httpResponseHead(request: request, status: .notFound)
                case let e as IOError:
                    body.write(staticString: "IOError (other)\r\n")
                    body.write(string: e.description)
                    body.write(staticString: "\r\n")
                    return httpResponseHead(request: request, status: .notFound)
                default:
                    body.write(string: "\(type(of: error)) error\r\n")
                    return httpResponseHead(request: request, status: .internalServerError)
                }
            }()
            body.write(string: "\(error)")
            body.write(staticString: "\r\n")
            ctx.write(self.wrapOutboundOut(.head(response)), promise: nil)
            ctx.write(self.wrapOutboundOut(.body(.byteBuffer(body))), promise: nil)
            ctx.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: nil)
            ctx.channel.close(promise: nil)
        }
        
        func responseHead(request: HTTPRequestHead, fileRegion region: FileRegion, contentType: String) -> HTTPResponseHead {
            var response = httpResponseHead(request: request, status: .ok)
            response.headers.add(name: "Content-Length", value: "\(region.endIndex)")
            response.headers.add(name: "Content-Type", value: contentType)
            return response
        }
        
        switch request {
        case .head(let request):
            self.keepAlive = request.isKeepAlive
            self.state.requestReceived()
            guard !request.uri.containsDotDot() else {
                let response = httpResponseHead(request: request, status: .forbidden)
                ctx.write(self.wrapOutboundOut(.head(response)), promise: nil)
                self.completeResponse(ctx, trailers: nil, promise: nil)
                return
            }
            let path = self.htdocsPath + "/" + path
            let fileHandleAndRegion = self.fileIO.openFile(path: path, eventLoop: ctx.eventLoop)
            fileHandleAndRegion.whenFailure {
                sendErrorResponse(request: request, $0)
            }
            fileHandleAndRegion.whenSuccess { (file, region) in
                var responseStarted = false
                let response = responseHead(request: request, fileRegion: region, contentType: path.contentType)
                return self.fileIO.readChunked(fileRegion: region,
                                               chunkSize: 32 * 1024,
                                               allocator: ctx.channel.allocator,
                                               eventLoop: ctx.eventLoop) { buffer in
                                                if !responseStarted {
                                                    responseStarted = true
                                                    ctx.write(self.wrapOutboundOut(.head(response)), promise: nil)
                                                }
                                                return ctx.writeAndFlush(self.wrapOutboundOut(.body(.byteBuffer(buffer))))
                    }.then { () -> EventLoopFuture<Void> in
                        let p = ctx.eventLoop.newPromise(of: Void.self)
                        self.completeResponse(ctx, trailers: nil, promise: p)
                        return p.futureResult
                    }.thenIfError { error in
                        if !responseStarted {
                            let response = self.httpResponseHead(request: request, status: .ok)
                            ctx.write(self.wrapOutboundOut(.head(response)), promise: nil)
                            var buffer = ctx.channel.allocator.buffer(capacity: 100)
                            buffer.write(string: "fail: \(error)")
                            ctx.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                            self.state.responseComplete()
                            return ctx.writeAndFlush(self.wrapOutboundOut(.end(nil)))
                        } else {
                            return ctx.close()
                        }
                    }.whenComplete {
                        _ = try? file.close()
                }
            }
        case .end:
            self.state.requestComplete()
        default:
            fatalError("oh noes: \(request)")
        }
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
    
    private func completeResponse(_ ctx: ChannelHandlerContext, trailers: HTTPHeaders?, promise: EventLoopPromise<Void>?) {
        self.state.responseComplete()
        
        let promise = self.keepAlive ? promise : (promise ?? ctx.eventLoop.newPromise())
        if !self.keepAlive {
            promise!.futureResult.whenComplete { ctx.close(promise: nil) }
        }
        self.handler = nil
        
        ctx.writeAndFlush(self.wrapOutboundOut(.end(trailers)), promise: promise)
    }
    
    
    func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
        let reqPart = self.unwrapInboundIn(data)
        if let handler = self.handler {
            handler(ctx, reqPart)
            return
        }
        
        switch reqPart {
        case .head(let request):
            if let path = request.uri.chopPrefix("/web/") {
                self.handler = { self.handleFile(ctx: $0, request: $1, path: path) }
                self.handler!(ctx, reqPart)
            } else {
                self.handler = { self.dynamicHandler(ctx: $0, request: $1) }
                self.handler!(ctx, reqPart)
            }
        case .body:
            break
        case .end:
            break
        }
    }
    
    func channelReadComplete(ctx: ChannelHandlerContext) {
        ctx.flush()
    }
    
    func userInboundEventTriggered(ctx: ChannelHandlerContext, event: Any) {
        switch event {
        case let evt as ChannelEvent where evt == ChannelEvent.inputClosed:
            // The remote peer half-closed the channel. At this time, any
            // outstanding response will now get the channel closed, and
            // if we are idle or waiting for a request body to finish we
            // will close the channel immediately.
            switch self.state {
            case .idle, .waitingForRequestBody:
                ctx.close(promise: nil)
            case .sendingResponse:
                self.keepAlive = false
            }
        default:
            ctx.fireUserInboundEventTriggered(event)
        }
    }
}

