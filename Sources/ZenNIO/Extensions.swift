//
//  Extensions.swift
//  ZenNIO
//
//  Created by admin on 21/12/2018.
//

import Foundation

extension Router {
    public func addAuthentication(handler: @escaping Login) {
        ZenIoC.shared.register { AuthenticationProvider() as AuthenticationProtocol }
        Authentication(handler: handler).makeRoutesAndHandlers(router: self)
    }
    public func addCORS() {
        ZenNIO.cors = true
    }
}

extension String {

    func chopPrefix(_ prefix: String) -> String? {
        if self.unicodeScalars.starts(with: prefix.unicodeScalars) {
            return String(self[self.index(self.startIndex, offsetBy: prefix.count)...])
        } else {
            return nil
        }
    }
    
    func containsDotDot() -> Bool {
        for idx in self.indices {
            if self[idx] == "." && idx < self.index(before: self.endIndex) && self[self.index(after: idx)] == "." {
                return true
            }
        }
        return false
    }

    public func fileExtension() -> String {
        return NSURL(fileURLWithPath: self).pathExtension ?? ""
    }
    
    public var contentType: String {
        let ext = self.fileExtension()
        switch ext {
        case "css":
            return "text/css"
        case "html":
            return "text/html; charset=utf-8"
        case "ico":
            return "image/x-icon"
        case "jpeg", "jpg":
            return "image/jpeg"
        case "js":
            return "application/x-javascript"
        case "gif":
            return "image/gif"
        case "png":
            return "image/png"
        case "txt":
            return "text/plain; charset=utf-8"
        case "mp4":
            return "video/mp4"
        case "plist":
            return "text/xml; charset=utf-8"
        case "json":
            return "application/json; charset=utf-8"
        case "csv":
            return "text/csv; charset=utf-8"
        case "pdf":
            return "application/pdf"
        case "doc", "docx":
            return "application/vnd.ms-word"
        case "xls", "xlsx":
            return "application/vnd.ms-excel"
        default:
            return "application/octet-stream"
        }
    }
}

extension Date {
    var rfc5322Date: String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale.current
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let compliantDate = dateFormatter.string(from: self)
        return compliantDate
    }
}

