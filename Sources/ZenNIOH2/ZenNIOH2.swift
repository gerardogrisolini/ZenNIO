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

public class ZenNIOH2: ZenNIOSSL {
    public override init(host: String = "::1", port: Int = 8888, router: Router, numberOfThreads: Int = System.coreCount) {
        super.init(host: host, port: port, router: router, numberOfThreads: numberOfThreads)
        self.httpProtocol = .v2
    }

    public override func httpConfig(channel: Channel) -> EventLoopFuture<Void> {
        return channel.configureHTTP2Pipeline(mode: .server) { (streamChannel, streamID) -> EventLoopFuture<Void> in
            return streamChannel.pipeline.addHandler(HTTP2ToHTTP1ServerCodec(streamID: streamID)).flatMap { () -> EventLoopFuture<Void> in
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
        var response = HTTPResponseHead(version: request.version, status: .ok)
        response.headers.add(name: "content-length", value: "\(region.endIndex)")
        response.headers.add(name: "content-type", value: contentType)
        return response
    }
    
    override public func processResponse(ctx: ChannelHandlerContext, response: HttpResponse) {
        ctx.eventLoop.execute {
            ctx.channel.getOption(HTTP2StreamChannelOptions.streamID).flatMap { (streamID) -> EventLoopFuture<Void> in
                var head = HTTPResponseHead(version: .init(major: 2, minor: 0), status: response.status)
                head.headers.add(name: "x-stream-id", value: String(Int(streamID)))
                for header in response.headers {
                    head.headers.add(name: header.name.lowercased(), value: header.value)
                }
                ctx.write(self.wrapOutboundOut(HTTPServerResponsePart.head(head)), promise: nil)
                if let body = response.body {
                    self.buffer = ctx.channel.allocator.buffer(capacity: body.count)
                    self.buffer.writeBytes(body)
                    ctx.channel.write(self.wrapOutboundOut(HTTPServerResponsePart.body(.byteBuffer(self.buffer))), promise: nil)
                }
                return ctx.channel.writeAndFlush(self.wrapOutboundOut(HTTPServerResponsePart.end(nil)))
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

