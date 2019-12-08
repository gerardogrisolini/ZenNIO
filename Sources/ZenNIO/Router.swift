//
//  Router.swift
//  ZenNIO
//
//  Created by admin on 21/12/2018.
//

import Foundation
import NIO
import NIOHTTP1
import Logging

extension HTTPMethod : Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine("\(self)")
    }
}

public typealias HttpHandler = (HttpRequest, HttpResponse) -> Void
public typealias ErrorHandler = (ChannelHandlerContext, HTTPRequestHead, Error) -> EventLoopFuture<HttpResponse>

struct Route {
    var filter: Bool
    var pattern: String
    var regex: NSRegularExpression?
    var handler: HttpHandler
    var params: [String: Array<String>.Index]
}

public class Router {
    private var routes: Dictionary<HTTPMethod, [Route]>
    
    public init() {
        routes = Dictionary<HTTPMethod, [Route]>()
    }
    
    public func get(_ uri: String, handler: @escaping HttpHandler) {
        addHandler(method: .GET, uri: uri, handler: handler)
    }
    
    public func post(_ uri: String, handler: @escaping HttpHandler) {
        addHandler(method: .POST, uri: uri, handler: handler)
    }
    
    public func put(_ uri: String, handler: @escaping HttpHandler) {
        addHandler(method: .PUT, uri: uri, handler: handler)
    }
    
    public func delete(_ uri: String, handler: @escaping HttpHandler) {
        addHandler(method: .DELETE, uri: uri, handler: handler)
    }
    
    func setFilter(_ value: Bool, methods: [HTTPMethod], url: String) {
        for method in methods {
            if routes[method] == nil { continue }
            for index in routes[method]!.indices {
                if url.last == "*" {
                    let count = url.count - (url.count == 2 ? 1 : 2)
                    let uri = url.prefix(count).description
                    if routes[method]![index].pattern.hasPrefix(uri) { //&& routes[method]![index].pattern != uri {
                        routes[method]![index].filter = value
                    }
                } else if routes[method]![index].pattern == url {
                    routes[method]![index].filter = value
                }
            }
        }
    }
    
    func getRoute(request: inout HttpRequest) -> Route? {
        guard request.head.method != .OPTIONS else {
            return Route(filter: false, pattern: request.head.uri, regex: nil, handler: { (_, response) in
                response.headers.add(name: "Access-Control-Max-Age", value: "86400")
                response.headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
                response.success(.noContent)
            }, params: [String : Array<String>.Index]())
        }
        
        let range = NSRange(location: 0, length: request.url.utf8.count)
        if let route = routes[request.head.method]?
            .first(where: {
                $0.regex == nil && $0.pattern == request.url
                || $0.regex?.firstMatch(in: request.url, options: [], range: range) != nil
            }) {
            for param in route.params {
                let value = request.paths[param.value].description
                request.setParam(key: param.key, value: value)
            }
            return route
        }
        return nil
    }
    
    fileprivate func append(method: HTTPMethod, route: Route) {
        if routes[method] == nil {
            routes[method] = []
        }
        routes[method]!.append(route)
    }
    
    func addHandler(method: HTTPMethod, uri: String, handler: @escaping HttpHandler) {
        var request = HttpRequest(head: HTTPRequestHead(version: HTTPVersion(major: 2, minor: 0), method: method, uri: uri))
        if getRoute(request: &request) != nil {
            let log = Logger.Message(stringLiteral: "⚠️ Duplicated route \(method) \(uri).")
            (ZenIoC.shared.resolve() as Logger).warning(log)
            return
        }
        
        let regex = RouteRegex.sharedInstance.buildRegex(fromPattern: uri)
        var params = [String : Array<String>.Index]()
        if let parameters = regex.2 {
            let uris = uri.split(separator: "/")
            for param in parameters {
                if let index = uris.firstIndex(where: { $0 == ":\(param)" }) {
                    params[param] = index
                }
            }
        }
        
        let route = Route(filter: false, pattern: uri, regex: regex.0, handler: handler, params: params)
        append(method: method, route: route)
    }
    
    func addDefaultPage() {
        let provider: HtmlProtocol = ZenNIO.session ? ZenIoC.shared.resolve() as HtmlProtocol : HtmlProvider()
        var request = HttpRequest(head: HTTPRequestHead(version: HTTPVersion(major: 2, minor: 0), method: .GET, uri: "/"))
        let route = getRoute(request: &request)
        
        if route == nil || ZenNIO.session {
            self.get("/assets/favicon.ico") { request, response in
                response.addHeader(.contentType, value: "image/x-icon")
                response.send(data: provider.icon)
                response.success()
            }
                    
            self.get("/assets/style.css") { request, response in
                response.addHeader(.contentType, value: "text/css")
                response.send(data: provider.style)
                response.success()
            }
            
            self.get("/assets/logo.png") { request, response in
                response.addHeader(.contentType, value: "image/png")
                response.send(data: provider.logo)
                response.success()
            }

            if route == nil {
                let log = Logger.Message(stringLiteral: "📎 The default route is empty, will be added the default page")
                (ZenIoC.shared.resolve() as Logger).info(log)

                self.get("/") { request, response in
                    let html = provider.defaultPage(ip: request.clientIp)
                    response.send(html: html)
                    response.success()
                }
            }
        }
    }
}


