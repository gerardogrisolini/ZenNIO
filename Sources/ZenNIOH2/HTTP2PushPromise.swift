//
//  HTTP2PushPromise.swift
//  ZenNIOH2
//
//  Created by Gerardo Grisolini on 25/05/2019.
//

import Foundation
import NIO
import NIOHTTP1
import NIOHTTP2
import NIOHPACK


public final class HTTP2PushPromise: ChannelOutboundHandler {
    public typealias OutboundIn = HTTP2Frame
    public typealias OutboundOut = HTTP2Frame
    
    private let streamID: HTTP2StreamID
    static var lastStreamID: Int = 0
    var pushPromises = [(HTTP2StreamID, String, Data)]()

    public init(streamID: HTTP2StreamID) {
        self.streamID = streamID
    }
    
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        var responsePart = self.unwrapOutboundIn(data)
        switch responsePart.payload {
        case .headers(let head):
            if let link = head.headers.filter({ $0.name == "link"}).first?.value {
                
                responsePart.payload = .headers(head)
                context.write(self.wrapOutboundOut(responsePart), promise: nil)

                print(HTTP2PushPromise.lastStreamID)
                let authority = head.headers.first { $0.name == "authority" }?.value ?? "localhost:8888"
                
                let links = link
                    .split(separator: ",")
                    .map { item -> String in
                        let val = item.split(separator: ";")
                        return val.first!
                            .replacingOccurrences(of: "<", with: "")
                            .replacingOccurrences(of: ">", with: "")
                            .trimmingCharacters(in: .whitespaces)
                    }
                
                for uri in links {
                    let url = URL(fileURLWithPath: "\(ZenNIOH2.htdocsPath)\(uri)")
                    let data = try! Data(contentsOf: url)
                        
                    HTTP2PushPromise.lastStreamID += 2
                    let pushStreamId = HTTP2StreamID(HTTP2PushPromise.lastStreamID)
                    pushPromises.append((pushStreamId, uri, data))
                    
                    let pushPromise = HTTP2Frame.FramePayload.PushPromise(
                        pushedStreamID: pushStreamId,
                        headers: HPACKHeaders([
                            (":method", "GET"),
                            (":scheme", "https"),
                            (":path", uri),
                            (":authority", authority)
                        ])
                    )
                    
                    let framePush = HTTP2Frame(streamID: streamID, payload: .pushPromise(pushPromise))
                    context.write(self.wrapOutboundOut(framePush), promise: nil)
                }
                
                let count = pushPromises.count
                for index in 0..<count {
                    let header = HTTP2Frame.FramePayload.Headers(
                        headers: HPACKHeaders([
                            (":status", "200"),
                            ("content-length", pushPromises[index].2.count.description),
                            ("content-type", pushPromises[index].1.contentType)
                        ])
                    )
                    let frameHeader = HTTP2Frame(streamID: pushPromises[index].0, payload: .headers(header))
                    context.write(self.wrapOutboundOut(frameHeader), promise: index == count - 1 ? promise : nil)
                }

            } else {
                context.write(self.wrapOutboundOut(responsePart), promise: promise)
            }
        case .data(_):
            for pushPromise in pushPromises{
                var buffer = context.channel.allocator.buffer(capacity: pushPromise.2.count)
                buffer.writeBytes(pushPromise.2)
                let payload = HTTP2Frame.FramePayload.Data(data: .byteBuffer(buffer), endStream: true)
                let frameData = HTTP2Frame(streamID: pushPromise.0, payload: .data(payload))
                context.write(self.wrapOutboundOut(frameData), promise: nil)
            }
            context.write(self.wrapOutboundOut(responsePart), promise: promise)
        default:
            break
        }
    }
}
