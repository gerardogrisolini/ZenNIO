//
//  HttpResponse.swift
//  ZenNIO
//
//  Created by admin on 20/12/2018.
//

import Foundation
import NIO
import NIOHTTP1
import Stencil

public class HttpResponse {
    var status: HTTPResponseStatus = .ok
    var headers = HTTPHeaders()
    var body: Data? = nil
    let promise: EventLoopPromise<HttpResponse>
    
    init(promise: EventLoopPromise<HttpResponse>) {
        self.promise = promise
        addHeader(.server, value: "ZenNIO")
        addHeader(.date, value: Date().rfc5322Date)
    }
    
    public func addHeader(_ name: HttpHeader, value: String) {
        headers.add(name: name.rawValue, value: value)
    }
    
    public func send<T: Codable>(json: T) throws {
        addHeader(.contentType, value: "application/json; charset=utf-8")
        let data = try JSONEncoder().encode(json)
        send(data: data)
    }
    
    public func send(data: Data) {
        body = data
    }
    
    public func send(text: String) {
        addHeader(.contentType, value: "text/plain; charset=utf-8")
        send(data: text.data(using: .utf8)!)
    }
    
    public func send(html: String) {
        addHeader(.contentType, value: "text/html; charset=utf-8")
        send(data: html.data(using: .utf8)!)
    }
    
    public func send(template: String, context: [String : Any]) throws {
        let fsLoader = FileSystemLoader(paths: ["templates/"])
        let environment = Environment(loader: fsLoader)
        let html = try environment.renderTemplate(name: template, context: context)
        addHeader(.contentType, value: "text/html; charset=utf-8")
        send(data: html.data(using: .utf8)!)
    }
    
    public func completed(_ status: HTTPResponseStatus = .ok) {
        self.status = status
        if status.code > 300 {
            let html = """
            <!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
            <html>
            <head>
            <title>\(status.reasonPhrase)</title>
            </head>
            <body>
            <p>\(headers[HttpHeader.server.rawValue].first!)</p>
            <h1>\(status.code) - \(status.reasonPhrase)</h1>
            </body>
            </html>
            """
            send(html: html)
        }
        addHeader(.contentLength, value: "\(body?.count ?? 0)")
        promise.succeed(result: self)
    }
}

