//
//  ZenNIO.swift
//  ZenNIO
//
//  Created by admin on 20/12/2018.
//

import Dispatch
import NIO
import NIOHTTP1
import Logging


public class ZenNIO {
    private var logger: Logger
    public let port: Int
    public let host: String
    public let numOfThreads: Int
    public let eventLoopGroup: EventLoopGroup
    public var fileIO: NonBlockingFileIO? = nil
    public var threadPool: NIOThreadPool? = nil
    public var channel: Channel?
    public var errorHandler: ErrorHandler? = nil

    public static var http: HttpProtocol = .v1
    public static var htdocsPath: String = ""
    static var cors = false
    static var session = false
    
    public init(
        host: String = "::1",
        port: Int = 8888,
        numberOfThreads: Int = System.coreCount,
        router: Router = Router(),
        logs: [Target] = [.console]
    ) {
        numOfThreads = numberOfThreads
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: numOfThreads)
        LoggingSystem.bootstrap(targets: logs)

        self.host = host
        self.port = port
        self.logger = .init(label: "ZenNIO")

        ZenIoC.shared.register { self.logger as Logger }
        ZenIoC.shared.register { router as Router }
    }
    
    deinit {
        stop()
    }
    
    public func addDocs(_ path: String = "webroot") {
        ZenNIO.htdocsPath = path
        threadPool = NIOThreadPool(numberOfThreads: numOfThreads)
        threadPool!.start()
        fileIO = NonBlockingFileIO(threadPool: threadPool!)
    }
    
    public func addSession() {
        ZenNIO.session = true
    }
    
    public func addCORS() {
        ZenNIO.cors = true
    }

    public func addError(handler: @escaping ErrorHandler) {
        errorHandler = handler
    }

    public func addAuthentication(handler: @escaping Login) {
        addSession()
        ZenIoC.shared.register { HtmlProvider() as HtmlProtocol }
        Authentication(handler: handler).makeRoutesAndHandlers()
    }
    
    public func setFilter(_ value: Bool, methods: [HTTPMethod], url: String) {
        (ZenIoC.shared.resolve() as Router).setFilter(value, methods: methods, url: url)
    }
    
    public func runSignal() {
        signal(SIGINT, SIG_IGN)
        let s = DispatchSource.makeSignalSource(signal: SIGINT)
        s.setEventHandler {
            self.stop()
        }
        s.resume()
    }

    public func start(signal: Bool = true) throws {
        defer {
            try! threadPool?.syncShutdownGracefully()
            try! eventLoopGroup.syncShutdownGracefully()
        }

        let bootstrap = ServerBootstrap(group: eventLoopGroup)
            // Specify backlog and enable SO_REUSEADDR for the server itself
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            // Set the handlers that are applied to the accepted Channels
            .childChannelInitializer { channel in
                return channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap { () -> EventLoopFuture<Void> in
                    channel.pipeline.addHandlers([
                        //NIOHTTPRequestDecompressor(limit: .none),
                        HttpResponseCompressor(),
                        ServerHandler(fileIO: self.fileIO, errorHandler: self.errorHandler)
                    ])
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
        
        guard let localAddress = channel?.localAddress else {
            fatalError("Address was unable to bind.")
        }
        
        (ZenIoC.shared.resolve() as Router).addDefaultPage()

        let log = "☯️ ZenNIO started on http://\(localAddress.ipAddress!):\(localAddress.port!) with \(numOfThreads) threads"
        logger.info(Logger.Message(stringLiteral: log))

        // This will never unblock as we don't close the ServerChannel
        if signal { runSignal() }
        try channel?.closeFuture.wait()
    }
    
    public func stop() {
        channel?.flush()
        print("")
        channel?.close().whenComplete({ result in
            let log = "☯️ ZenNIO terminated"
            self.logger.info(Logger.Message(stringLiteral: log))
        })
    }
}
