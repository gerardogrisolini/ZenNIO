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
                    streamChannel.pipeline.addHandler(ServerHandlerH2(htdocsPath: self.htdocsPath))
                }.flatMap { () -> EventLoopFuture<Void> in
                    streamChannel.pipeline.addHandler(ErrorHandler())
                }
            }.flatMap { (_: HTTP2StreamMultiplexer) in
                return channel.pipeline.addHandler(ErrorHandler())
            }
    }
}

public class ServerHandlerH2: ServerHandler {
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
//                let lenght = 32 * 1024
//                let count = response.body.readableBytes
//                var index = 0
//                while index < count {
//                    let end = index + lenght > count ? count - index : lenght
//                    if let bytes = response.body.getSlice(at: index, length: end) {
//                        ctx.write(self.wrapOutboundOut(.body(.byteBuffer(bytes))), promise: nil)
//                    }
//                    index += end
//                }
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

