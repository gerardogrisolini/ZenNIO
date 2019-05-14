//
//  ZenNIOH2.swift
//  ZenNIOH2
//
//  Created by admin on 08/04/2019.
//

import NIO
import NIOHTTP1
import NIOHTTP2
import ZenNIO
import ZenNIOSSL
//import NIOHTTPCompression

public class ZenNIOH2: ZenNIOSSL {
    public override init(host: String = "::1", port: Int = 8888, router: Router, numberOfThreads: Int = System.coreCount) {
        super.init(host: host, port: port, router: router, numberOfThreads: numberOfThreads)
        self.httpProtocol = .v2
    }
    
    public override func httpConfig(channel: Channel) -> EventLoopFuture<Void> {
        return channel.configureHTTP2Pipeline(mode: .server) { (streamChannel, streamID) -> EventLoopFuture<Void> in
            return streamChannel.pipeline.addHandler(HTTP2ToHTTP1ServerCodec(streamID: streamID)).flatMap { () -> EventLoopFuture<Void> in
//                streamChannel.pipeline.addHandlers([
//                    HTTPResponseCompressor(initialByteBufferCapacity: 0),
//                    ServerHandlerH2(fileIO: self.fileIO, htdocsPath: self.htdocsPath)
//                ])
                streamChannel.pipeline.addHandler(ServerHandlerH2(fileIO: self.fileIO, htdocsPath: self.htdocsPath))
                }.flatMap { () -> EventLoopFuture<Void> in
                    streamChannel.pipeline.addHandler(ErrorHandler())
            }
            }.flatMap { (_: HTTP2StreamMultiplexer) in
                return channel.pipeline.addHandler(ErrorHandler())
        }
    }
}

public class ServerHandlerH2: ServerHandler {
    
    override public func responseHead(request: HTTPRequestHead, fileRegion region: FileRegion, contentType: String) -> HTTPResponseHead {
        var response = HTTPResponseHead(version: .init(major: 2, minor: 0), status: .ok)
        response.headers.add(name: "content-length", value: "\(region.endIndex)")
        response.headers.add(name: "content-type", value: contentType)
        return response
    }
    
    override public func errorHead(html: String, status: HTTPResponseStatus) -> HTTPResponseHead {
        var head = HTTPResponseHead(version: .init(major: 2, minor: 0), status: status)
        head.headers.add(name: "content-length", value: "\(html.count)")
        head.headers.add(name: "content-type", value: "text/html; charset=utf-8")
        return head
    }

    override public func processResponse(ctx: ChannelHandlerContext, response: HttpResponse) {
        ctx.eventLoop.execute {
            ctx.channel.getOption(HTTP2StreamChannelOptions.streamID).flatMap { (streamID) -> EventLoopFuture<Void> in
                var head = HTTPResponseHead(version: .init(major: 2, minor: 0), status: response.status)
                head.headers.add(name: "x-stream-id", value: String(Int(streamID)))
                for header in response.headers {
                    head.headers.add(name: header.name.lowercased(), value: header.value)
                }
                ctx.channel.write(self.wrapOutboundOut(.head(head)), promise: nil)
                ctx.write(self.wrapOutboundOut(.body(.byteBuffer(response.body))), promise: nil)
                self.state.responseComplete()
                return ctx.writeAndFlush(self.wrapOutboundOut(.end(nil)))
                }.whenComplete { _ in
                    ctx.close(promise: nil)
            }
        }
    }
}

final class ErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Never
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("Server received error: \(error)")
        context.close(promise: nil)
    }
}

