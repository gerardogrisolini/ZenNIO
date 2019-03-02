//
//  DataModel.swift
//  ZenSMTP
//
//  Created by admin on 01/03/2019.
//


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

public struct Email {
    var senderName: String?
    var senderEmail: String
    
    var recipientName: String?
    var recipientEmail: String
    
    var subject: String
    
    var body: String
}
