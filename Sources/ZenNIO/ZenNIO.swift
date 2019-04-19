//
//  ZenNIO.swift
//  ZenNIO
//
//  Created by admin on 20/12/2018.
//

import NIO
import NIOHTTP1
import NIOHTTPCompression

open class ZenNIO {
    public var httpProtocol: HttpProtocol = .v1
    public let port: Int
    public let host: String
    public var htdocsPath: String = ""
    public let numOfThreads: Int
    public let eventLoopGroup: EventLoopGroup
//    public var fileIO: NonBlockingFileIO? = nil
//    private let threadPool: NIOThreadPool
    private var channel: Channel?
    
    static var router = Router()
    static var sessions = HttpSession()
    static var cors = false
    static var session = false
    
    
    public init(
        host: String = "::1",
        port: Int = 8888,
        router: Router = Router(),
        numberOfThreads: Int = System.coreCount
    ) {
        numOfThreads = numberOfThreads
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: numOfThreads)
//        threadPool = NIOThreadPool(numberOfThreads: 2)
        
        self.host = host
        self.port = port
        ZenNIO.router = router
    }
    
    deinit {
        stop()
    }
    
    public func addWebroot(path: String = "webroot") {
        htdocsPath = path
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
        defer {
//            try! threadPool.syncShutdownGracefully()
            try! eventLoopGroup.syncShutdownGracefully()
        }
        
//        if !htdocsPath.isEmpty {
//            threadPool.start()
//            fileIO = NonBlockingFileIO(threadPool: threadPool)
//        }
        
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
    
    open func tlsConfig(channel: Channel) -> EventLoopFuture<Void> {
        let p = channel.eventLoop.makePromise(of: Void.self)
        p.succeed(())
        return p.futureResult
    }
    
    open func httpConfig(channel: Channel) -> EventLoopFuture<Void> {
        return channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap { () -> EventLoopFuture<Void> in
            channel.pipeline.addHandlers([
                HTTPResponseCompressor(initialByteBufferCapacity: 0),
                ServerHandler(htdocsPath: self.htdocsPath)
            ])
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
