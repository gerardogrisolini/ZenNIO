//
//  HTTP2ServerHandler.swift
//  ZenNIOH2
//
//  Created by Gerardo Grisolini on 20/05/2019.
//

import NIO
import NIOHTTP1
import NIOHTTP2

public class HTTP2ServerHandler: ServerHandler {
        
    override public func processResponse(ctx: ChannelHandlerContext, response: HttpResponse) {
        ctx.eventLoop.execute {
            ctx.channel.getOption(HTTP2StreamChannelOptions.streamID).flatMap { (streamID) -> EventLoopFuture<Void> in
                var head = HTTPResponseHead(version: .init(major: 2, minor: 0), status: response.status)
                head.headers.add(name: "x-stream-id", value: String(Int(streamID)))
                for header in response.headers {
                    head.headers.add(name: header.name.lowercased(), value: header.value)
                }
                head.headers.remove(name: "transfer-encoding")
                ctx.write(self.wrapOutboundOut(.head(head)), promise: nil)
                ctx.write(self.wrapOutboundOut(.body(.byteBuffer(response.body))), promise: nil)
                self.state.responseComplete()
                return ctx.writeAndFlush(self.wrapOutboundOut(.end(nil)))
            }.whenComplete { _ in
                ctx.close(promise: nil)
            }
        }
    }
    
    override public func responseHead(request: HTTPRequestHead, fileRegion region: FileRegion, contentType: String) -> HTTPResponseHead {
        var head = HTTPResponseHead(version: .init(major: 2, minor: 0), status: .ok)
        head.headers.add(name: "content-length", value: "\(region.endIndex)")
        head.headers.add(name: "content-type", value: contentType)
        return head
    }
}
