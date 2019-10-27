//
//  ZenNIO.swift
//  ZenNIO
//
//  Created by admin on 20/12/2018.
//

import NIO
import NIOHTTP1
import NIOHTTP2
import NIOHTTPCompression
import NIOSSL

open class ZenNIO {
    public let http: HttpProtocol
    public let port: Int
    public let host: String
    public static var htdocsPath: String = ""
    public let numOfThreads: Int
    public let eventLoopGroup: EventLoopGroup
    public var fileIO: NonBlockingFileIO? = nil
    private let threadPool: NIOThreadPool
    private var channel: Channel?
    
    static var router = Router()
    static var cors = false
    static var session = false
    
    
    public init(
        host: String = "::1",
        port: Int = 8888,
        router: Router = Router(),
        http: HttpProtocol = .v1,
        numberOfThreads: Int = System.coreCount
    ) {
        numOfThreads = numberOfThreads
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: numOfThreads)
        threadPool = NIOThreadPool(numberOfThreads: numOfThreads)

        self.host = host
        self.port = port
        self.http = http
        ZenNIO.router = router
    }
    
    deinit {
        stop()
    }
    
    public func addWebroot(path: String = "webroot") {
        ZenNIO.htdocsPath = path
    }
    
    public func addCORS() {
        ZenNIO.cors = true
    }
    
    public func addAuthentication(handler: @escaping Login) {
        ZenNIO.session = true
        ZenIoC.shared.register { AuthenticationProvider() as AuthenticationProtocol }
        Authentication(handler: handler).makeRoutesAndHandlers(router: ZenNIO.router)
    }
    
    public func setFilter(_ value: Bool, methods: [HTTPMethod], url: String) {
        ZenNIO.router.setFilter(value, methods: methods, url: url)
    }
    
    public func start() throws {
        if !ZenNIO.htdocsPath.isEmpty {
            threadPool.start()
            fileIO = NonBlockingFileIO(threadPool: threadPool)
        }

        let bootstrap = ServerBootstrap(group: eventLoopGroup)
            // Specify backlog and enable SO_REUSEADDR for the server itself
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            // Set the handlers that are applied to the accepted Channels
            .childChannelInitializer { channel in
                return self.tlsConfig(channel: channel).flatMap({ () -> EventLoopFuture<Void> in
                    self.httpConfig(channel: channel)
                })
            }
            // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
            .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
        
        defer {
            try! threadPool.syncShutdownGracefully()
            try! eventLoopGroup.syncShutdownGracefully()
        }

        channel = try { () -> Channel in
            return try bootstrap.bind(host: host, port: port).wait()
            }()
        
        guard let localAddress = channel!.localAddress else {
            fatalError("Address was unable to bind.")
        }
        
        print("☯️  ZenNIO started on \(localAddress) with \(numOfThreads) threads")
        
        // This will never unblock as we don't close the ServerChannel
        try channel!.closeFuture.wait()
    }
    
    public func stop() {
        channel?.flush()
        print("")
        channel?.close().whenComplete({ result in
            print("☯️  ZenNIO stopped")
        })
    }
    
    
    // HTTP
    
    open func httpConfig(channel: Channel) -> EventLoopFuture<Void> {
        if http == .v1 {
            return channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap { () -> EventLoopFuture<Void> in
                channel.pipeline.addHandlers([
                    NIOHTTPRequestDecompressor(limit: .none),
                    HttpResponseCompressor(),
                    ServerHandler(fileIO: self.fileIO)
                ])
            }
        }
        
        return channel.configureHTTP2Pipeline(mode: .server) { (streamChannel, streamID) -> EventLoopFuture<Void> in
            //return streamChannel.pipeline.addHandler(HTTP2PushPromise(streamID: streamID)).flatMap { () -> EventLoopFuture<Void> in
                return streamChannel.pipeline.addHandler(HTTP2ToHTTP1ServerCodec(streamID: streamID)).flatMap { () -> EventLoopFuture<Void> in
                    //streamChannel.pipeline.addHandler(HTTP2ServerHandler(fileIO: self.fileIO))
                    streamChannel.pipeline.addHandlers([
                        NIOHTTPRequestDecompressor(limit: .none),
                        HttpResponseCompressor(http: .v2),
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
    
    
    // SSL
    
    private var sslContext: NIOSSLContext?
    
    public func addSSL(certFile: String, keyFile: String) throws {
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
    }

    open func tlsConfig(channel: Channel) -> EventLoopFuture<Void> {
        if let sslContext = sslContext {
            return channel.pipeline.addHandler(try! NIOSSLServerHandler(context: sslContext))
        }
        
        let p = channel.eventLoop.makePromise(of: Void.self)
        p.succeed(())
        return p.futureResult
    }

    
    // HTTP2
    
    final class ErrorHandler: ChannelInboundHandler {
        typealias InboundIn = Never
        
        func errorCaught(context: ChannelHandlerContext, error: Error) {
            print("Server received error: \(error)")
            context.close(promise: nil)
        }
    }
}

///// Wrapping Swift.debugPrint() within DEBUG flag
//func debugPrint(_ object: Any) {
//    // Only allowing in DEBUG mode
//    #if DEBUG
//    Swift.print(object)
//    #endif
//}

