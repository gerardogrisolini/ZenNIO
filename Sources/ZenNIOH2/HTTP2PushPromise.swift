//
//  HTTP2PushPromise.swift
//  ZenNIOH2
//
//  Created by Gerardo Grisolini on 17/05/2019.
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
    public static var lastStreamID: Int = 2

    public init(streamID: HTTP2StreamID) {
        self.streamID = streamID
    }

    var pushPromises = [(HTTP2StreamID, String, Data)]()
    
    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let responsePart = self.unwrapOutboundIn(data)
        switch responsePart.payload {
        case .headers(let head):
            print(head.headers)
            context.write(self.wrapOutboundOut(responsePart), promise: promise)
            
            if let link = head.headers.filter({ $0.name == "link"}).first?.value {
                
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
                    if let data = FileManager.default.contents(atPath: "/Users/gerardo/Downloads/webroot\(uri)") {
                        HTTP2PushPromise.lastStreamID += 2
                        let pushStreamId = HTTP2StreamID(HTTP2PushPromise.lastStreamID)
                        pushPromises.append((pushStreamId, uri, data))
                        print("\(HTTP2PushPromise.lastStreamID): \(uri)")

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
                }
                
                for pushPromise in pushPromises {
                    let header = HTTP2Frame.FramePayload.Headers(
                        headers: HPACKHeaders([
                            (":status", "200"),
                            ("content-length", pushPromise.2.count.description),
                            ("content-type", pushPromise.1.contentType)
                        ])
                    )
                    let frameHeader = HTTP2Frame(streamID: pushPromise.0, payload: .headers(header))
                    context.write(self.wrapOutboundOut(frameHeader), promise: nil)
                }
            }
        default:
            for pushPromise in pushPromises {
                var buffer = context.channel.allocator.buffer(capacity: pushPromise.2.count)
                buffer.writeBytes(pushPromise.2)
                var payload = HTTP2Frame.FramePayload.Data(data: .byteBuffer(buffer))
                payload.endStream = true
                let frameData = HTTP2Frame(streamID: pushPromise.0, payload: .data(payload))
                context.write(self.wrapOutboundOut(frameData), promise: nil)
            }
            context.write(self.wrapOutboundOut(responsePart), promise: promise)
            pushPromises.removeAll()
        }
    }
}
