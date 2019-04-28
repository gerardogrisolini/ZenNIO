//
//  HttpResponse.swift
//  ZenNIO
//
//  Created by admin on 20/12/2018.
//

import Foundation
import NIO
import NIOHTTP1
import NIOHTTPCompression

public class HttpResponse {
    public var status: HTTPResponseStatus = .ok
    public var headers = HTTPHeaders()
    public var body: ByteBuffer
    let promise: EventLoopPromise<HttpResponse>?

    init(body: ByteBuffer, promise: EventLoopPromise<HttpResponse>? = nil) {
        self.body = body
        self.promise = promise
        addHeader(.server, value: "ZenNIO")
        addHeader(.date, value: Date().rfc5322Date)
    }
    
    public func addHeader(_ name: HttpHeader, value: String) {
        headers.add(name: name.rawValue, value: value)
    }
    
    public func send<T: Codable>(json: T) throws {
        addHeader(.contentType, value: "application/json; charset=utf-8")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(json)
        send(data: data)
    }
    
    public func send(data: Data) {
        body.reserveCapacity(data.count)
        body.writeBytes(data)
    }
    
    public func send(text: String) {
        addHeader(.contentType, value: "text/plain; charset=utf-8")
        send(data: text.data(using: .utf8)!)
    }
    
    public func send(html: String) {
        addHeader(.contentType, value: "text/html; charset=utf-8")
        send(data: html.data(using: .utf8)!)
    }
    
    public func completed(_ status: HTTPResponseStatus = .ok) {
        self.status = status
        if status.code > 300 {
            let html = """
<!DOCTYPE HTML PUBLIC "-//IETF//DTD HTML 2.0//EN">
<html>
<head><title>\(status.reasonPhrase)</title></head>
<body>
<p>\(headers[HttpHeader.server.rawValue].first!)</p>
<h1>\(status.code) - \(status.reasonPhrase)</h1>
</body>
</html>
"""
            send(html: html)
        }
        
        addHeader(.contentLength, value: "\(body.readableBytes)")
        promise?.succeed(self)
    }
}

