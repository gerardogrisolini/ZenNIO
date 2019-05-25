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
import NIOHTTPCompression

public class ZenNIOH2: ZenNIOSSL {
    
    public override init(host: String = "::1", port: Int = 8888, router: Router, numberOfThreads: Int = System.coreCount) {
        super.init(host: host, port: port, router: router, numberOfThreads: numberOfThreads)
        self.httpProtocol = .v2
    }
    
    public override func httpConfig(channel: Channel) -> EventLoopFuture<Void> {
        return channel.configureHTTP2Pipeline(mode: .server) { (streamChannel, streamID) -> EventLoopFuture<Void> in
            //return streamChannel.pipeline.addHandler(HTTP2PushPromise(streamID: streamID)).flatMap { () -> EventLoopFuture<Void> in
                return streamChannel.pipeline.addHandler(HTTP2ToHTTP1ServerCodec(streamID: streamID)).flatMap { () -> EventLoopFuture<Void> in
                    streamChannel.pipeline.addHandler(HTTP2ServerHandler())
                }.flatMap { () -> EventLoopFuture<Void> in
                    channel.pipeline.addHandler(ErrorHandler())
                }
            //}
        }.flatMap { (_: HTTP2StreamMultiplexer) in
            return channel.pipeline.addHandler(ErrorHandler())
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

