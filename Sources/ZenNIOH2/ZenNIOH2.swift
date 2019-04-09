//
//  ZenNIOH2.swift
//  ZenNIOH2
//
//  Created by admin on 08/04/2019.
//

import NIO
import NIOHTTP2
import ZenNIO

public class ZenNIOH2: ZenNIO {
    public override func httpConfig(channel: Channel) -> EventLoopFuture<Void> {
        return channel.configureHTTP2Pipeline(mode: .server) { (streamChannel: Channel, streamID: HTTP2StreamID) -> EventLoopFuture<Void> in
            streamChannel.pipeline.addHandler(HTTP2ToHTTP1ServerCodec(streamID: streamID)).flatMap { (c) -> EventLoopFuture<Void> in
                streamChannel.pipeline.addHandler(ServerHandler(fileIO: self.fileIO, htdocsPath: self.htdocsPath))
            }
        }.flatMap { (_: HTTP2StreamMultiplexer) in
            channel.pipeline.addHandler(ErrorHandler())
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

