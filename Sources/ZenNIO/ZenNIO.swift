//
//  ZenNIO.swift
//  ZenNIO
//
//  Created by admin on 20/12/2018.
//

import NIO
import NIOHTTP1

open class ZenNIO {
    public var httpProtocol: HttpProtocol = .v1
    public let port: Int
    public let host: String
    public var htdocsPath: String = ""
    public let numOfThreads: Int
    public var sslContext: Any? = nil
    public let eventLoopGroup: EventLoopGroup
    public var fileIO: NonBlockingFileIO? = nil
    private let threadPool: NIOThreadPool
    
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
        threadPool = NIOThreadPool(numberOfThreads: numOfThreads)
        
        self.host = host
        self.port = port
        ZenNIO.router = router
    }
    
    public let cipherSuites = "ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-CBC-SHA384:ECDHE-ECDSA-AES256-CBC-SHA:ECDHE-ECDSA-AES128-CBC-SHA256:ECDHE-ECDSA-AES128-CBC-SHA:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-CBC-SHA384:ECDHE-RSA-AES128-CBC-SHA256:ECDHE-RSA-AES128-CBC-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA"
    
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
    
    public func setFilter(_ value: Bool, methods: [HTTPMethod], url: String) {
        ZenNIO.router.setFilter(value, methods: methods, url: url)
    }
    
    static func getRoute(request: inout HttpRequest) -> Route? {
        return self.router.getRoute(request: &request)
    }
    
    public func start() throws {
        defer {
            try! threadPool.syncShutdownGracefully()
            try! eventLoopGroup.syncShutdownGracefully()
        }
        
        if !htdocsPath.isEmpty {
            threadPool.start()
            fileIO = NonBlockingFileIO(threadPool: threadPool)
        }
        
        let bootstrap = ServerBootstrap(group: eventLoopGroup)
            // Specify backlog and enable SO_REUSEADDR for the server itself
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            // Set the handlers that are applied to the accepted Channels
            .childChannelInitializer { channel in
                //self.tlsConfig(channel: channel)
                return self.httpConfig(channel: channel)
            }
            // Enable TCP_NODELAY and SO_REUSEADDR for the accepted Channels
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)
            .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
        
        let channel = try { () -> Channel in
            return try bootstrap.bind(host: host, port: port).wait()
            }()
        
        guard let localAddress = channel.localAddress else {
            fatalError("Address was unable to bind.")
        }
        
        print("ZenNIO started on \(localAddress) with \(numOfThreads) threads")
        
        // This will never unblock as we don't close the ServerChannel
        try channel.closeFuture.wait()
        
        print("ZenNIO closed")
    }
    
    open func tlsConfig(channel: Channel) {
    }

    open func httpConfig(channel: Channel) -> EventLoopFuture<Void> {
        return channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap { (c) -> EventLoopFuture<Void> in
            channel.pipeline.addHandler(ServerHandler(fileIO: self.fileIO, htdocsPath: self.htdocsPath))
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
