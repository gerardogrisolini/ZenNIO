//
//  ZenNIO.swift
//  ZenNIO
//
//  Created by admin on 20/12/2018.
//

import NIO
import NIOHTTP1
import NIOHTTP2
import NIOOpenSSL

public class ZenNIO {
    
    private var sslContext: SSLContext? = nil
    private var httpProtocol: HttpProtocol = .v1
    
    public let port: Int
    public let host: String
    public var htdocsPath: String = ""
    static var router = Router()
    static var sessions = HttpSession()
    static var cors = false
    static var session = false
    
    public init(
        host: String = "::1",
        port: Int = 8888,
        router: Router = Router()
        ) {
        self.host = host
        self.port = port
        ZenNIO.router = router
    }
    
    private let cipherSuites = "ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-CBC-SHA384:ECDHE-ECDSA-AES256-CBC-SHA:ECDHE-ECDSA-AES128-CBC-SHA256:ECDHE-ECDSA-AES128-CBC-SHA:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-CBC-SHA384:ECDHE-RSA-AES128-CBC-SHA256:ECDHE-RSA-AES128-CBC-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA"
    
    public func addWebroot(path: String = "webroot") {
        htdocsPath = path
        ZenNIO.router.initFolder(webroot: path)
    }
    
    public func addCORS() {
        ZenNIO.cors = true
    }
    
    public func addAuthentication(handler: @escaping Login) {
        ZenNIO.session = true
        ZenIoC.shared.register { AuthenticationProvider() as AuthenticationProtocol }
        Authentication(handler: handler).makeRoutesAndHandlers(router: ZenNIO.router)
    }
    
    public func addSSL(certFile: String, keyFile: String, http: HttpProtocol = .v1) throws {
        self.httpProtocol = http
        let config = TLSConfiguration.forServer(
            certificateChain: [.file(certFile)],
            privateKey: .file(keyFile),
            cipherSuites: cipherSuites,
            tls13CipherSuites: "",
            minimumTLSVersion: .tlsv11,
            maximumTLSVersion: .tlsv12,
            certificateVerification: .noHostnameVerification,
            trustRoots: .default,
            applicationProtocols: [httpProtocol.rawValue]
        )
        sslContext = try! SSLContext(configuration: config)
    }
    
    static func getRoute(request: inout HttpRequest) -> Route? {
        return self.router.getRoute(request: &request)
    }
    
    public func start() throws {
        let threadPool = BlockingIOThreadPool(numberOfThreads: System.coreCount)
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        defer {
            try! threadPool.syncShutdownGracefully()
            try! group.syncShutdownGracefully()
        }
        
        var fileIO: NonBlockingFileIO? = nil
        if !htdocsPath.isEmpty {
            threadPool.start()
            fileIO = NonBlockingFileIO(threadPool: threadPool)
        }
        
        let bootstrap = ServerBootstrap(group: group)
            // Specify backlog and enable SO_REUSEADDR for the server itself
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
        
        // Set the handlers that are applied to the accepted Channels
        if let sslContext = self.sslContext {
            if httpProtocol == .v1 {
                _ = bootstrap.childChannelInitializer { channel in
                    return channel.pipeline.add(handler: try! OpenSSLServerHandler(context: sslContext)).then {
                        return channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).then {
                            channel.pipeline.add(handler: ServerHandler(fileIO: fileIO, htdocsPath: self.htdocsPath))
                        }
                    }
                }
            } else {
                _ = bootstrap.childChannelInitializer { channel in
                    return channel.pipeline.add(handler: try! OpenSSLServerHandler(context: sslContext)).then {
                        return channel.pipeline.add(handler: HTTP2Parser(mode: .server)).then {
                            let multiplexer = HTTP2StreamMultiplexer { (channel, streamID) -> EventLoopFuture<Void> in
                                return channel.pipeline.add(handler: HTTP2ToHTTP1ServerCodec(streamID: streamID)).then { () -> EventLoopFuture<Void> in
                                    channel.pipeline.add(handler: ServerHandler(fileIO: fileIO, htdocsPath: self.htdocsPath, http: .v2))
                                }
                            }
                            return channel.pipeline.add(handler: multiplexer)
                        }
                    }
                }
            }
        } else {
            _ = bootstrap.childChannelInitializer { channel in
                return channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).then {
                    channel.pipeline.add(handler: ServerHandler(fileIO: fileIO, htdocsPath: self.htdocsPath))
                }
            }
        }
        
        // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
        _ = bootstrap.childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
            .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
        
        let channel = try { () -> Channel in
            return try bootstrap.bind(host: host, port: port).wait()
            }()
        
        guard let localAddress = channel.localAddress else {
            fatalError("Address was unable to bind.")
        }
        
        let http = sslContext != nil ? "HTTPS" : "HTTP"
        print("\(http) ZenNIO started on\(localAddress)")
        
        // This will never unblock as we don't close the ServerChannel
        try channel.closeFuture.wait()
        
        print("ZenNIO closed")
    }
}

/// Wrapping Swift.debugPrint() within DEBUG flag
func debugPrint(_ object: Any) {
    // Only allowing in DEBUG mode
    #if DEBUG
    Swift.print(object)
    #endif
}


