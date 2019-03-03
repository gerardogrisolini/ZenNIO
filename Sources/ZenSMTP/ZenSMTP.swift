//
//  ZenSMTP.swift
//  ZenSMTP
//
//  Created by admin on 01/03/2019.
//

import NIO
import NIOSSL

public class ZenSMTP {

    static var config: ServerConfiguration!
    private var clientHandler: NIOSSLClientHandler? = nil

    init(config: ServerConfiguration) {
        ZenSMTP.config = config
        if let cert = config.cert, let key = config.key {
            let configuration = TLSConfiguration.forServer(
                certificateChain: [cert],
                privateKey: key)
            let sslContext = try! NIOSSLContext(configuration: configuration)
            clientHandler = try! NIOSSLClientHandler(context: sslContext)
        }
    }
    
    public func send(email: Email, handler: @escaping (Error?) -> Void) {

        let printHandler: (String) -> Void = { str in
            print(str)
        }
        
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let emailSentPromise: EventLoopPromise<Void> = group.next().makePromise()
        let bootstrap = ClientBootstrap(group: group)
            // Enable SO_REUSEADDR.
            .channelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .channelInitializer { channel in
                let handlers: [ChannelHandler] = [
                    PrintEverythingHandler(handler: printHandler),
                    SMTPResponseDecoder(),
                    SMTPRequestEncoder(),
                    SendEmailHandler(configuration: ZenSMTP.config,
                                     email: email,
                                     allDonePromise: emailSentPromise)
                ]
                if let clientHandler = self.clientHandler {
                    return channel.pipeline.addHandler(clientHandler).flatMap {
                        channel.pipeline.addHandlers(handlers)
                    }
                } else {
                    return channel.pipeline.addHandlers(handlers)
                }
            }
            .connect(host: ZenSMTP.config.hostname, port: ZenSMTP.config.port)
        
        bootstrap.cascadeFailure(to: emailSentPromise)
        
        func completed(_ error: Error?) {
            bootstrap.whenSuccess { $0.close(promise: nil) }
            handler(nil)
            try! group.syncShutdownGracefully()
        }

        emailSentPromise.futureResult
            .map { _ in
                completed(nil)
             }
            .whenFailure { error in
                completed(error)
            }
    }
}
