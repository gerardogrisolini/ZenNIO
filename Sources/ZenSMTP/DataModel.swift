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
    var hostname: String
    var port: Int
    var username: String
    var password: String
    var cert: NIOSSLCertificateSource?
    var key: NIOSSLPrivateKeySource?
    
    init(hostname: String,
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
    var fileName: String
    var contentType: String
    var data: Data
    
    init(fileName: String,
         contentType: String,
         data: Data) {
        self.fileName = fileName
        self.contentType = contentType
        self.data = data
    }
}

public struct Email {
    var fromName: String?
    var fromEmail: String
    var toName: String?
    var toEmail: String
    
    var subject: String
    var body: String
    var attachments: [Attachment]
}
