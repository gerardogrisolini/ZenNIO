//
//  Authentication.swift
//  ZenNIO
//
//  Created by admin on 22/12/2018.
//

import Foundation
import NIO
import Logging

public typealias Login = (_ username: String, _ password: String) -> EventLoopFuture<String>

public struct Account : Codable {
    public var username: String = ""
    public var password: String = ""
}

public struct Token : Codable {
    public var basic: String = ""
    public var bearer: String = ""
    
    public init(basic: String) {
        self.basic = basic
    }
    
    public init(bearer: String) {
        self.bearer = bearer
    }
}

class Authentication {
    
    private let provider: HtmlProtocol
    private let handler: Login
    
    init(handler: @escaping Login) {
        provider = ZenIoC.shared.resolve() as HtmlProtocol
        self.handler = handler
    }
    
    func makeRoutesAndHandlers() {
        
        let router = ZenIoC.shared.resolve() as Router

        router.get("/assets/scripts.js") { request, response in
            response.addHeader(.contentType, value: "text/javascript")
            response.send(data: self.provider.script())
            return response.success()
        }

        router.get("/auth") { request, response in
            //response.addHeader(.link, value: "</assets/logo.png>; rel=preload; as=image, </assets/style.css>; rel=preload; as=style, </assets/scripts.js>; rel=preload; as=script")
            //response.addHeader(.cache, value: "no-cache")
            //response.addHeader(.cache, value: "max-age=1440") // 1 days
            //response.addHeader(.expires, value: Date(timeIntervalSinceNow: TimeInterval(1440.0 * 60.0)).rfc5322Date)
            
            let html = self.provider.auth(ip: request.clientIp)
            response.send(html: html)
            response.success()
        }
        
        router.post("/api/logout") { request, response in
            if let session = request.session {
                if let uniqueID = session.uniqueID {
                    let log = Logger.Message(stringLiteral: "👎 Logout \(uniqueID)")
                    (ZenIoC.shared.resolve() as Logger).info(log)
                }
                HttpSession.remove(id: session.id)
            }
            
            response.addHeader(.setCookie, value: "token=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;")
            response.addHeader(.setCookie, value: "sessionId=; expires=Thu, 01 Jan 1970 00:00:00 UTC; path=/;")
            response.success(.noContent)
        }
        
        router.post("/api/login") { request, response in
            do {
                guard let data = request.bodyData,
                    let account = try? JSONDecoder().decode(Account.self, from: data) else {
                    throw HttpError.badRequest("body")
                }
                
                let login = self.handler(account.username, account.password)
                login.whenComplete { result in
                    switch result {
                    case .success(let uniqueID):
                        let session = HttpSession.new(id: request.session!.id, uniqueID: uniqueID)
                        request.session = session
                        try? response.send(json: session.token!)
                        response.addHeader(.setCookie, value: "token=\(session.token!.bearer); expires=Sat, 01 Jan 2050 00:00:00 UTC; path=/;")
                        response.success()
                        
                        let log = Logger.Message(stringLiteral: "👍 Login \(request.session!.uniqueID!)")
                        (ZenIoC.shared.resolve() as Logger).info(log)

                    case .failure(_):
                        response.success(.unauthorized)
                    }
                }
            } catch HttpError.badRequest(let reason) {
                response.failure(.badRequest(reason))
            } catch {
                response.failure(.internalError(error.localizedDescription))
            }
        }
    }
}
