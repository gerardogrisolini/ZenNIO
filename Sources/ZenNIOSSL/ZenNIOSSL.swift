//
//  File.swift
//  
//
//  Created by Gerardo Grisolini on 28/10/2019.
//

import NIO
import NIOSSL
import NIOHTTP2
import ZenNIO


extension ZenNIO {

    private func addSSL(certFile: String, keyFile: String, http: HttpProtocol) throws -> NIOSSLContext {
        let cert = try NIOSSLCertificate.fromPEMFile(certFile)
        let config = TLSConfiguration.forServer(
            certificateChain: [.certificate(cert.first!)],
            privateKey: .file(keyFile),
//            cipherSuites: self.cipherSuites,
//            minimumTLSVersion: .tlsv11,
//            maximumTLSVersion: .tlsv12,
//            certificateVerification: .noHostnameVerification,
//            trustRoots: .default,
            applicationProtocols: [http.rawValue]
        )
        ZenNIO.http = http
        return try NIOSSLContext(configuration: config)
    }
    
    public func startSecure(certFile: String, keyFile: String, http: HttpProtocol = .v1) throws {
        defer {
            try! threadPool?.syncShutdownGracefully()
            try! eventLoopGroup.syncShutdownGracefully()
        }

        let sslContext = try addSSL(certFile: certFile, keyFile: keyFile, http: http)
        let bootstrap = ServerBootstrap(group: eventLoopGroup)
            // Specify backlog and enable SO_REUSEADDR for the server itself
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            // Set the handlers that are applied to the accepted Channels
            .childChannelInitializer { channel in
                return channel.pipeline.addHandler(try! NIOSSLServerHandler(context: sslContext)).flatMap { () -> EventLoopFuture<Void> in
                    if ZenNIO.http == .v1 {
                        return channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap { () -> EventLoopFuture<Void> in
                            channel.pipeline.addHandlers([
                                //NIOHTTPRequestDecompressor(limit: .none),
                                HttpResponseCompressor(),
                                ServerHandler(fileIO: self.fileIO, errorHandler: self.errorHandler)
                            ])
                        }
                    }
                    return channel.configureHTTP2Pipeline(mode: .server) { (streamChannel, streamID) -> EventLoopFuture<Void> in
                        //return streamChannel.pipeline.addHandler(HTTP2PushPromise(streamID: streamID)).flatMap { () -> EventLoopFuture<Void> in
                            return streamChannel.pipeline.addHandler(HTTP2ToHTTP1ServerCodec(streamID: streamID)).flatMap { () -> EventLoopFuture<Void> in
                                streamChannel.pipeline.addHandlers([
                                    //NIOHTTPRequestDecompressor(limit: .none),
                                    HttpResponseCompressor(),
                                    HTTP2ServerHandler(fileIO: self.fileIO, errorHandler: self.errorHandler)
                                ])
                            }.flatMap { () -> EventLoopFuture<Void> in
                                channel.pipeline.addHandlers(ErrorHandler())
                            }
                        //}
                    }.flatMap { (_: HTTP2StreamMultiplexer) in
                        return channel.pipeline.addHandler(ErrorHandler())
                    }
                }
            }
            // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
            .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
        
        channel = try { () -> Channel in
            return try bootstrap.bind(host: host, port: port).wait()
        }()
        
        guard let localAddress = channel.localAddress else {
            fatalError("Address was unable to bind.")
        }
        
        print("☯️  ZenNIO started on https://\(localAddress.ipAddress!):\(localAddress.port!) with \(numOfThreads) threads")

        // This will never unblock as we don't close the ServerChannel
        try channel.closeFuture.wait()
    }
}

// HTTP2

final class ErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Never
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("Server received error: \(error)")
        context.close(promise: nil)
    }
}
