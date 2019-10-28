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


private struct Holder {
    static var sslContext: NIOSSLContext!
}

extension ZenNIOProtocol {

    func addSSL(certFile: String, keyFile: String, http: HttpProtocol = .v1) throws {
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
        Holder.sslContext = try! NIOSSLContext(configuration: config)
        ZenNIO.http = http
    }
    
    func tlsConfig(channel: Channel) -> EventLoopFuture<Void> {
        return channel.pipeline.addHandler(try! NIOSSLServerHandler(context: Holder.sslContext))
    }
    
    func httpConfig(channel: Channel) -> EventLoopFuture<Void> {
        if ZenNIO.http == .v1 {
            return channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap { () -> EventLoopFuture<Void> in
                channel.pipeline.addHandlers([
                    //NIOHTTPRequestDecompressor(limit: .none),
                    HttpResponseCompressor(),
                    ServerHandler(fileIO: self.fileIO)
                ])
            }
        }
        
        return channel.configureHTTP2Pipeline(mode: .server) { (streamChannel, streamID) -> EventLoopFuture<Void> in
            //return streamChannel.pipeline.addHandler(HTTP2PushPromise(streamID: streamID)).flatMap { () -> EventLoopFuture<Void> in
                return streamChannel.pipeline.addHandler(HTTP2ToHTTP1ServerCodec(streamID: streamID)).flatMap { () -> EventLoopFuture<Void> in
                    streamChannel.pipeline.addHandlers([
                        HttpResponseCompressor(),
                        HTTP2ServerHandler(fileIO: self.fileIO)
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

// HTTP2

final class ErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Never
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("Server received error: \(error)")
        context.close(promise: nil)
    }
}
