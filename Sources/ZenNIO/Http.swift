//
//  Http.swift
//  ZenNIO
//
//  Created by admin on 20/12/2018.
//

import Foundation
import NIO
import NIOHTTP1


public enum HttpProtocol: String  {
    case v1 = "http/1.1"
    case v2 = "h2"
}

public enum TLSMethod {
    //case tlsV1
    case tlsV1_1
    case tlsV1_2
}

public enum HttpHeader: String  {
    case status = ":status"
    case contentType = "Content-Type"
    case date = "Date"
    case location = "Location"
    case contentLength = "Content-Length"
    case authorization = "Authorization"
    case server = "Server"
    case connection = "Connection"
    case acceptRanges = "Accept-Ranges"
    case setCookie = "Set-Cookie"
    case cookie = "Cookie"
    case userAgent = "User-Agent"
    case link = "Link"
    case cache = "Cache-Control"
    case expires = "Expires"
    case referer = "Referer"
    //case push = "X-Http2-Push"
}

public enum HttpError: Swift.Error {
    case unauthorized
    case notFound
    case badRequest(String)
    case internalError(String)
    case custom(UInt, String)
}

public struct Session {
    public let id: String
    public var date: Date
    public var uniqueID: Any? = nil
    public var token: Token? = nil
    
    public init(id: String) {
        self.id = id
        self.date = Date()
    }
}
