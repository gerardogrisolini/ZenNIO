//
//  PrintEverythingHandler.swift
//  ZenSMTP
//
//  Created by admin on 01/03/2019.
//

import Foundation
import NIO

final class PrintEverythingHandler: ChannelDuplexHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer
    typealias OutboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    
    private let handler: (String) -> Void

    init(handler: @escaping (String) -> Void) {
        self.handler = handler
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = self.unwrapInboundIn(data)
        self.handler("☁️ \(String(decoding: buffer.readableBytesView, as: UTF8.self))")
        context.fireChannelRead(data)
    }
    
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let buffer = self.unwrapOutboundIn(data)
        if buffer.readableBytesView.starts(with: Data(ZenSMTP.config.password.utf8).base64EncodedData()) {
            self.handler("📱 <password hidden>\r\n")
        } else {
            self.handler("📱 \(String(decoding: buffer.readableBytesView, as: UTF8.self))")
        }
        context.write(data, promise: promise)
    }
}

