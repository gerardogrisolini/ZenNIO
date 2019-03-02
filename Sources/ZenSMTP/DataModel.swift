//
//  DataModel.swift
//  ZenSMTP
//
//  Created by admin on 01/03/2019.
//

import Foundation

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
}

public struct Attachment {
    var fileName: String
    var contentType: String
    var data: Data
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
