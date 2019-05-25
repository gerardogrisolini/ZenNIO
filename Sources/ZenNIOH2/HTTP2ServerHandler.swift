//
//  HTTP2ServerHandler.swift
//  ZenNIOH2
//
//  Created by Gerardo Grisolini on 20/05/2019.
//

import NIO
import NIOHTTP1
import NIOHTTP2
import ZenNIO

public class HTTP2ServerHandler: ServerHandler {
        
    override public func processResponse(ctx: ChannelHandlerContext, response: HttpResponse) {
        ctx.eventLoop.execute {
            ctx.channel.getOption(HTTP2StreamChannelOptions.streamID).flatMap { (streamID) -> EventLoopFuture<Void> in
                
                let streamId = String(Int(streamID))
                
                var head = HTTPResponseHead(version: .init(major: 2, minor: 0), status: response.status)
                head.headers.add(name: "x-stream-id", value: streamId)
                for header in response.headers {
                    head.headers.add(name: header.name.lowercased(), value: header.value)
                }
                ctx.channel.write(self.wrapOutboundOut(.head(head)), promise: nil)
                
                //self.pushPromise(ctx: ctx, headers: head.headers, streamID: streamId)
                
                ctx.write(self.wrapOutboundOut(.body(.byteBuffer(response.body))), promise: nil)
                self.state.responseComplete()
                return ctx.writeAndFlush(self.wrapOutboundOut(.end(nil)))
            }.whenComplete { _ in
                ctx.close(promise: nil)
            }
        }
    }
    
//    override public func responseHead(request: HTTPRequestHead, fileRegion region: FileRegion, contentType: String) -> HTTPResponseHead {
//        var head = HTTPResponseHead(version: .init(major: 2, minor: 0), status: .ok)
//        head.headers.add(name: "content-length", value: "\(region.endIndex)")
//        head.headers.add(name: "content-type", value: contentType)
//        return head
//    }

    func pushPromise(ctx: ChannelHandlerContext, headers: HTTPHeaders, streamID: String) {
        if let link = headers.filter({ $0.name == "link"}).first?.value {
            
            let links = link
                .split(separator: ",")
                .map { item -> String in
                    let val = item.split(separator: ";")
                    return val.first!
                        .replacingOccurrences(of: "<", with: "")
                        .replacingOccurrences(of: ">", with: "")
                        .trimmingCharacters(in: .whitespaces)
            }
            
            var parts = [(streamID: Int, contentType: String, buffer: ByteBuffer)]()
            
            for uri in links {
                HTTP2Response.lastStreamID += 2
                do {
                    let data = try getStaticFile(uri: uri)
                    var buffer = ctx.channel.allocator.buffer(capacity: data.count)
                    buffer.writeBytes(data)
                    parts.append((HTTP2Response.lastStreamID, uri.contentType, buffer))
                    
                    /// PUSH PROMISE
                    var pushPromise = HTTPResponseHead(version: .init(major: 2, minor: 0), status: .ok)
                    //pushPromise.headers.add(name: "x-stream-id", value: streamID)
                    pushPromise.headers.add(name: "push-stream-id", value: HTTP2Response.lastStreamID.description)
                    pushPromise.headers.add(name: "path", value: uri)
                    ctx.channel.write(self.wrapOutboundOut(.head(pushPromise)), promise: nil)
                } catch {
                    print(error)
                }
            }
            
            /// HEADS
            for part in parts {
                var head = HTTPResponseHead(version: .init(major: 2, minor: 0), status: .ok)
                head.headers.add(name: "x-stream-id", value: part.streamID.description)
                head.headers.add(name: "content-length", value: part.buffer.readableBytes.description)
                head.headers.add(name: "content-type", value: part.contentType)
                ctx.channel.write(self.wrapOutboundOut(.head(head)), promise: nil)
//            }
//
//            /// BODYS
//            for part in parts {
                let dataLen = part.buffer.readableBytes
                let chunkSize = 32 * 1024
                let fullChunks = Int(dataLen / chunkSize)
                let totalChunks = fullChunks + (dataLen % 1024 != 0 ? 1 : 0)
                
                for chunkCounter in 0..<totalChunks {
                    let chunkBase = chunkCounter * chunkSize
                    var diff = chunkSize
                    if (chunkCounter == totalChunks - 1) {
                        diff = dataLen - chunkBase
                    }
                    let buffer = part.buffer.getSlice(at: chunkBase, length: diff)!
        
                    ctx.write(self.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                }
            }
        }
    }
}
