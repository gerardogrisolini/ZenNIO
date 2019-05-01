//
//  HttpSession.swift
//  ZenNIO
//
//  Created by Gerardo Grisolini on 30/10/2018.
//

import Foundation

public struct HttpSession {
    
    private var sessions = [Session]()
    
    public mutating func new(id: String = "", uniqueID: String? = nil) -> Session {
        var base64 = id
        if id.isEmpty {
            base64 = UUID().uuidString.data(using: .utf8)!.base64EncodedString()
        }
        
        var session = Session(id: base64)
        base64 = UUID().uuidString.data(using: .utf8)!.base64EncodedString()
        session.token = Token(bearer: base64)
        session.uniqueID = uniqueID
        
        sessions.append(session)
        
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
                }
                return new(id: id, uniqueID: nil)
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


