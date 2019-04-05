//
//  HttpSession.swift
//  ZenNIO
//
//  Created by Gerardo Grisolini on 30/10/2018.
//

import Foundation

struct HttpSession {
    
    private var sessions = [Session]()
    
    mutating func new(id: String = "", token: Token? = nil) -> Session {
        var base64 = id
        if id.isEmpty {
            let date = Date()
            let data = "\(date.timeIntervalSinceNow)-\(date.timeIntervalSinceReferenceDate)".data(using: .utf8)!
            base64 = data.base64EncodedString()
        }
        
        var session = Session(id: base64)
        session.token = token
        
        return session
    }
    
    mutating func set(session: Session) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
            return
        }
        sessions.append(session)
    }
    
    mutating func get(authorization: String, cookies: String) -> Session? {
        if !authorization.isEmpty {
            let bearer = authorization.replacingOccurrences(of: "Bearer ", with: "")
            if let index = sessions.firstIndex(where: { $0.token?.bearer == bearer }) {
                return sessions[index]
            }
        }
        
        if !cookies.isEmpty {
            let items = cookies.split(separator: ";")
            if let item = items.first(where: { $0.contains("sessionId") }) {
                let id = item.replacingOccurrences(of: "sessionId=", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                if let index = sessions.firstIndex(where: { $0.id == id }) {
                    return sessions[index]
                } else {
                    if let token = items.first(where: { $0.contains("token") }) {
                        let bearer = token.replacingOccurrences(of: "token=", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        return new(id: id, token: Token(bearer: bearer))
                    }
                    return new(id: id, token: nil)
                }
            }
        }
        
        return nil
    }
    
    mutating func remove(id: String) {
        sessions.removeAll { session -> Bool in
            return session.id == id
        }
    }
}

