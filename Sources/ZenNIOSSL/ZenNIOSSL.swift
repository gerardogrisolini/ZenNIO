//
//  ZenNIOSSL.swift
//  ZenNIOSSL
//
//  Created by admin on 08/04/2019.
//

import NIO
import NIOSSL
import ZenNIO

open class ZenNIOSSL: ZenNIO {
    public var sslContext: NIOSSLContext!
    
    public func addSSL(certFile: String, keyFile: String) throws {
        let config = TLSConfiguration.forServer(
            certificateChain: [.file(certFile)],
            privateKey: .file(keyFile),
            cipherSuites: self.cipherSuites,
            minimumTLSVersion: .tlsv11,
            maximumTLSVersion: .tlsv12,
            certificateVerification: .noHostnameVerification,
            trustRoots: .default,
            applicationProtocols: [httpProtocol.rawValue]
        )
        sslContext = try! NIOSSLContext(configuration: config)
    }
    
    open override func tlsConfig(channel: Channel) -> EventLoopFuture<Void> {
        let sslHandler = try! NIOSSLServerHandler(context: sslContext)
        return channel.pipeline.addHandler(sslHandler)
    }
}
