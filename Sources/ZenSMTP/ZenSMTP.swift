//
//  ZenNIOSMTP.swift
//  ZenSMTP
//
//  Created by admin on 01/03/2019.
//

import NIO
import Network

public class ZenSMTP {

    static var config: ServerConfiguration!
    
    init(config: ServerConfiguration) {
        ZenSMTP.config = config
    }
    
    public func send(email: Email, handler: @escaping (Error?) -> Void) {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
//        defer {
//            try! group.syncShutdownGracefully()
//        }
        let commHandler: (String) -> Void = { str in
            print(str)
        }
        let emailSentPromise: EventLoopPromise<Void> = group.next().makePromise()
        let bootstrap = ClientBootstrap(group: group)
            // Enable SO_REUSEADDR.
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHandlers([
                    PrintEverythingHandler(handler: commHandler),
                    //LineBasedFrameDecoder(),
                    SMTPResponseDecoder(),
                    SMTPRequestEncoder(),
                    SendEmailHandler(configuration: ZenSMTP.config,
                                     email: email,
                                     allDonePromise: emailSentPromise)
                ])
            }
            .connect(host: ZenSMTP.config.hostname, port: ZenSMTP.config.port)
        
        bootstrap.cascadeFailure(to: emailSentPromise)
        
        emailSentPromise.futureResult.map {
            bootstrap.whenSuccess { $0.close(promise: nil) }
            handler(nil)
            try! group.syncShutdownGracefully()
        }.whenFailure { error in
            bootstrap.whenSuccess { $0.close(promise: nil) }
            handler(error)
            try! group.syncShutdownGracefully()
        }
    }
}

