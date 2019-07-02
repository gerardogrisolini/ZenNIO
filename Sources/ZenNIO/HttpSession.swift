//
//  HttpSession.swift
//  ZenNIO
//
//  Created by Gerardo Grisolini on 30/10/2018.
//

import Foundation

public struct HttpSession {
    
    private static var sessions = [Session]()
    
    static func new(id: String = "", uniqueID: Any? = nil) -> Session {
        var base64 = id
        if id.isEmpty {
            base64 = UUID().uuidString.data(using: .utf8)!.base64EncodedString()
        }
        
        if let index = sessions.firstIndex(where: { $0.id == base64 }) {
            if let id = uniqueID {
                sessions[index].uniqueID = id
                sessions[index].token = newToken()
            }
            return sessions[index]
        } else {
            var session = Session(id: base64)
            if let id = uniqueID {
                session.uniqueID = id
                session.token = newToken()
            }
            sessions.append(session)
            return session
        }
    }
    
    private static func newToken() -> Token {
        let base64 = UUID().uuidString.data(using: .utf8)!.base64EncodedString()
        return Token(bearer: base64)
    }
    
    static func set(session: Session) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
            return
        }
        sessions.append(session)
    }
    
    static func get(authorization: String, cookies: String) -> Session? {
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
                }
                return new(id: id)
            }
        }
        
        return nil
    }
    
    static func remove(id: String) {
        sessions.removeAll { session -> Bool in
            return session.id == id
        }
    }
}


