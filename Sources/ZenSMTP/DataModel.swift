//
//  DataModel.swift
//  ZenSMTP
//
//  Created by admin on 01/03/2019.
//

import Foundation
import NIOSSL

enum SMTPRequest {
    case sayHello(serverName: String)
    case beginAuthentication
    case authUser(String)
    case authPassword(String)
    case mailFrom(String)
    case recipient(String)
    case data
    case transferData(Email)
    case quit
}

enum SMTPResponse {
    case ok(Int, String)
    case error(String)
}

public struct ServerConfiguration {
    public var hostname: String
    public var port: Int
    public var username: String
    public var password: String
    public var cert: NIOSSLCertificateSource?
    public var key: NIOSSLPrivateKeySource?
    
    public init(hostname: String,
         port: Int,
         username: String,
         password: String,
         cert: NIOSSLCertificateSource?,
         key: NIOSSLPrivateKeySource?) {
        self.hostname = hostname
        self.port = port
        self.username = username
        self.password = password
        self.cert = cert
        self.key = key
    }
}

public struct Attachment {
    public var fileName: String
    public var contentType: String
    public var data: Data
    
    public init(fileName: String,
         contentType: String,
         data: Data) {
        self.fileName = fileName
        self.contentType = contentType
        self.data = data
    }
}

public struct Email {
    public var fromName: String?
    public var fromEmail: String
    public var toName: String?
    public var toEmail: String
    
    public var subject: String
    public var body: String
    public var attachments: [Attachment]
    
    public init(
        fromName: String? = nil,
        fromEmail: String,
        toName: String? = nil,
        toEmail: String,
        subject: String,
        body: String,
        attachments: [Attachment]
    ) {
        self.fromName = fromName
        self.fromEmail = fromEmail
        self.toName = toName
        self.toEmail = toEmail
        self.subject = subject
        self.body = body
        self.attachments = attachments
    }
}
