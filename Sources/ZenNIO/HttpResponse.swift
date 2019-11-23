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

    public init(body: ByteBuffer, promise: EventLoopPromise<HttpResponse>? = nil) {
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
    
    public func failure(_ error: HttpError) {
        switch error {
        case .unauthorized:
            status = .unauthorized
        case .notFound:
            status = .notFound
        case .badRequest(let reason):
            send(data: reason.data(using: .utf8)!)
            status = .badRequest
        case .internalError(let reason):
            send(data: reason.data(using: .utf8)!)
            status = .internalServerError
        case .custom(let code, let reason):
            status = .custom(code: code, reasonPhrase: reason)
        }
        promise?.fail(error)
    }
    
    public func success(_ status: HTTPResponseStatus = .ok) {
        self.status = status
        
//        if status.code > 300 {
//            failure(HttpError.custom(status.code, status.reasonPhrase))
//        } else {
            promise?.succeed(self)
//        }
    }
}

