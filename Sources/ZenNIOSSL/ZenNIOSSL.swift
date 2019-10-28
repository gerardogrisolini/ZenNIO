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

open class ZenNIOSSL: ZenNIO {
//    public let cipherSuites = "ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-CBC-SHA384:ECDHE-ECDSA-AES256-CBC-SHA:ECDHE-ECDSA-AES128-CBC-SHA256:ECDHE-ECDSA-AES128-CBC-SHA:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-CBC-SHA384:ECDHE-RSA-AES128-CBC-SHA256:ECDHE-RSA-AES128-CBC-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA"
    public var sslContext: NIOSSLContext!
    
    public func addSSL(certFile: String, keyFile: String, http: HttpProtocol = .v1) throws {
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
        sslContext = try! NIOSSLContext(configuration: config)
        ZenNIO.http = http
    }
    
    open override func tlsConfig(channel: Channel) -> EventLoopFuture<Void> {
        return channel.pipeline.addHandler(try! NIOSSLServerHandler(context: sslContext))
    }
    
    open override func httpConfig(channel: Channel) -> EventLoopFuture<Void> {
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
