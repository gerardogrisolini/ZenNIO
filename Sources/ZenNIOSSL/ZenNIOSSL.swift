//
//  ZenNIOSSL.swift
//  ZenNIOSSL
//
//  Created by admin on 08/04/2019.
//

import NIO
import NIOSSL
import ZenNIO

public class ZenNIOSSL: ZenNIO {
    var ssl: NIOSSLContext {
        return sslContext as! NIOSSLContext
    }
    
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
    
    public override func tlsConfig(channel: Channel) {
        let sslHandler = try! NIOSSLServerHandler(context: ssl)
        _ = channel.pipeline.addHandler(sslHandler)
    }
}
