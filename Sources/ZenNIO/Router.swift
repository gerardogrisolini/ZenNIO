//
//  Router.swift
//  ZenNIO
//
//  Created by admin on 21/12/2018.
//

import Foundation
import NIOHTTP1

extension HTTPMethod : Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine("\(self)")
    }
}

public typealias HttpHandler = ((HttpRequest, HttpResponse) -> ())

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
                response.completed(.noContent)
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
            print("Warning: duplicated route \(method) \(uri).")
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
}


