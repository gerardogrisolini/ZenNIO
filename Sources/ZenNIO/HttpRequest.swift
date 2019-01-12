//
//  HttpRequest.swift
//  ZenNIO
//
//  Created by admin on 20/12/2018.
//

import Foundation
import NIO
import NIOHTTP1

public class HttpRequest {
    public var eventLoop: EventLoop!
    public var clientIp: String!
    public var session: Session?
    public let head: HTTPRequestHead
    public let contentType: String
    private(set) public var body: [UInt8]
    private var params = Dictionary<String, Any>()
    let paths: [Substring]
    var url: String
    
    init(head: HTTPRequestHead, body: [UInt8] = []) {
        self.head = head
        self.url = head.uri
        self.paths = head.uri.split(separator: "/")
        self.body = body
        contentType = head.headers[HttpHeader.contentType.rawValue].first ?? ""
        self.parseHeadParameters()
    }

    var authorization: String {
        return head.headers[HttpHeader.authorization.rawValue].first ?? ""
    }

    var cookies: String {
        return head.headers[HttpHeader.cookie.rawValue].joined(separator: ",")
    }

    var referer: String {
        return head.headers[HttpHeader.referer.rawValue].first ?? ""
    }

    var isAuthenticated: Bool {
        if let token = session?.token {
            if authorization == "Bearer \(token.bearer)" {
                return true
            }
            if cookies.contains("token=\(token.bearer)") {
                return true
            }
        }
        return false
    }
    
    func setSession(_ session: Session) {
        self.session = session
    }

    func addContent(bytes: [UInt8]) {
        body.append(contentsOf: bytes)
    }

    public var bodyString: String? {
        return String(bytes: body, encoding: .utf8)
    }
    
    public var bodyData: Data? {
        guard body.count > 0 else {
            return nil
        }
        return Data(body)
    }

    func parseRequest() {
        parseBodyParameters()
        parseBodyMultipart()
    }

    func setParam(key: String, value: Any) {
        params[key] = value
    }
    
    public func getParam(_ type: Int.Type, key: String) -> Int? {
        if let param = params[key] as? String {
            return Int(param)
        }
        return nil
    }
    
    public func getParam(_ type: UUID.Type, key: String) -> UUID? {
        if let uuid = params[key] as? String {
            return UUID(uuidString: uuid)
        }
        return nil
    }

    public func getParam(_ type: String.Type, key: String) -> String? {
        return params[key] as? String
    }

    public func getParam(_ type: Data.Type, key: String) -> Data? {
        return params[key] as? Data
    }

    fileprivate func parseHeadParameters() {
        guard  let end = url.firstIndex(of: "?")  else {
            return
        }
        url = url[url.startIndex..<end].description
        
        let start = head.uri.index(end, offsetBy: 1)
        let paramString = head.uri[start...].description
    
        let paramArray = paramString.split(separator: "&")
        paramArray.forEach { param in
            let values = param.split(separator: "=")
            if values.count == 2 {
                params[values[0].description] = values[1].description
            }
        }
    }

    fileprivate func parseBodyParameters() {
        if !contentType.hasPrefix("application/x-www-form-urlencoded") { return }

        if let paramString = bodyString?.removingPercentEncoding?.replacingOccurrences(of: "+", with: " ") {
            let paramArray = paramString.split(separator: "&")
            paramArray.forEach { param in
                let values = param.split(separator: "=")
                if values.count == 2 {
                    params[values[0].description] = values[1].description
                }
            }
        }
    }
    
    fileprivate func parseBodyMultipart() {
        if !contentType.hasPrefix("multipart") { return }
        
        var result : [Int] = []
        let boundary = contentType.replacingOccurrences(of: "multipart/form-data; boundary=", with: "--")
        let bytes = [UInt8](boundary.utf8)
        let len = bytes.count
        var count = 0
        for i in 0..<body.count {
            if body[i] == bytes[count] {
                count += 1
            } else {
                count = 0
            }
            if count == len {
                result.append(i + 2)
                count = 0
            }
          }
        
        if result.count == 0 { return }
        
        for p in 0..<(result.count - 1) {
            count = result[p]
            var end = 0
            while end == 0 {
                count += 1
                if body[count] == 10 {
                    end = count
                }
            }
            if let part = String(bytes: body[result[p]..<end], encoding: .utf8) {
                let parts = part.split(separator: ";")
                
                var name = parts[1]
                    .replacingOccurrences(of: " name=\"", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                name.removeLast()
                
                let start = end + 3
                end = result[p + 1] - len - 4
                
                if parts.count > 2 {
                    var filename = parts[2]
                        .replacingOccurrences(of: " filename=\"", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    filename.removeLast()
                    
                    params[name] = filename
                    params[filename] = Data(body[start...end])
                } else {
                    if let value = String(bytes: body[start...end], encoding: .utf8) {
                        params[name] = value
                    }
                }
            }
        }
    }
}
