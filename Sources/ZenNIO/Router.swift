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
    let secure: Bool
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
    
    public func get(_ uri: String, secure: Bool = false, handler: @escaping HttpHandler) {
        addHandler(secure: secure, method: .GET, uri: uri, handler: handler)
    }
    
    public func post(_ uri: String, secure: Bool = false, handler: @escaping HttpHandler) {
        addHandler(secure: secure, method: .POST, uri: uri, handler: handler)
    }

    public func put(_ uri: String, secure: Bool = false, handler: @escaping HttpHandler) {
        addHandler(secure: secure, method: .PUT, uri: uri, handler: handler)
    }

    public func delete(_ uri: String, secure: Bool = false, handler: @escaping HttpHandler) {
        addHandler(secure: secure, method: .DELETE, uri: uri, handler: handler)
    }
    
    func getRoute(request: inout HttpRequest) -> Route? {
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
    
    private func addHandler(secure: Bool = false, method: HTTPMethod, uri: String, handler: @escaping HttpHandler) {
//        var request = HttpRequest(head: HTTPRequestHead(version: HTTPVersion(major: 2, minor: 0), method: method, uri: uri))
//        if getRoute(request: &request) != nil {
//            print("Warning: overwritten route \(method) \(uri) already recorded.")
//        }

        let regex = RouteRegex.sharedInstance.buildRegex(fromPattern: uri)
        //debugPrint(regex)
        var params = [String : Array<String>.Index]()
        if let parameters = regex.2 {
            let uris = uri.split(separator: "/")
            for param in parameters {
                if let index = uris.firstIndex(where: { $0 == ":\(param)" }) {
                    params[param] = index
                }
            }
        }
        
        let route = Route(secure: secure, pattern: uri, regex: regex.0, handler: handler, params: params)
        if routes[method] == nil {
            routes[method] = []
        }
        routes[method]!.append(route)
    }
}
