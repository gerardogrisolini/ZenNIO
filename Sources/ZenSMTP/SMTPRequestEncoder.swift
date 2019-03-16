//
//  SMTPRequestEncoder.swift
//  ZenSMTP
//
//  Created by admin on 01/03/2019.
//

import NIO
import NIOFoundationCompat
import Foundation

final class SMTPRequestEncoder: MessageToByteEncoder, ChannelHandler {

    typealias OutboundIn = SMTPRequest
    
    func encode(data: SMTPRequest, out: inout ByteBuffer) throws {
        switch data {
        case .sayHello(serverName: let server):
            out.writeString("HELO \(server)")
        case .mailFrom(let from):
            out.writeString("MAIL FROM:<\(from)>")
        case .recipient(let rcpt):
            out.writeString("RCPT TO:<\(rcpt)>")
        case .data:
            out.writeString("DATA")
        case .transferData(let email):
            let date = Date()
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            let dateFormatted = dateFormatter.string(from: date)

            out.writeString("From: \(formatMIME(emailAddress: email.fromEmail, name: email.fromName))\r\n")
            out.writeString("To: \(formatMIME(emailAddress: email.toEmail, name: email.toName))\r\n")
            out.writeString("Date: \(dateFormatted)\r\n")
            out.writeString("Message-ID: <\(date.timeIntervalSince1970)\(email.fromEmail.drop { $0 != "@" })>\r\n")
            out.writeString("Subject: \(email.subject)\r\n")

            if email.attachments.isEmpty {
                out.writeString("Content-Type: text/html; charset=utf-8\r\n\r\n")
                out.writeString("\(email.body)</br>")
            } else {
                let boundary = "boundary-\(UUID().uuidString)"
                out.writeString("Content-Type: multipart/mixed; boundary=\(boundary)\r\n\r\n")
 
                out.writeString("--\(boundary)\r\n")
                out.writeString("Content-Type: text/html; charset=utf-8\r\n")
                out.writeString("Content-Transfer-Encoding: base64\r\n\r\n")
                out.writeString(email.body.data(using: .utf8)!.base64EncodedString())
                out.writeString("\r\n")

                for attachment in email.attachments {
                    out.writeString("--\(boundary)\r\n")
                    out.writeString("Content-Type: \(attachment.contentType); name=\(attachment.fileName)\r\n")
                    out.writeString("Content-Disposition: attachment; filename=\(attachment.fileName)\r\n")
                    out.writeString("Content-Transfer-Encoding: base64\r\n")
                    out.writeString("X-Attachment-Id: \(Int.random(in: 1000...99999))\r\n\r\n")
                    out.writeString(attachment.data.base64EncodedString())
                    out.writeString("\r\n")
                }
            }
            
            out.writeString("\r\n.")
        case .quit:
            out.writeString("QUIT")
        case .beginAuthentication:
            out.writeString("AUTH LOGIN")
        case .authUser(let user):
            let userData = Data(user.utf8)
            out.writeBytes(userData.base64EncodedData())
        case .authPassword(let password):
            let passwordData = Data(password.utf8)
            out.writeBytes(passwordData.base64EncodedData())
        }
        
        out.writeString("\r\n")
    }
    
    func formatMIME(emailAddress: String, name: String?) -> String {
        if let name = name {
            return "\(name) <\(emailAddress)>"
        } else {
            return emailAddress
        }
    }
}
