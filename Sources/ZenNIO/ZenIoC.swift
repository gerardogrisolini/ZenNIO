//
//  ZenIoC.swift
//  ZenNIO
//
//  Created by Gerardo Grisolini on 25/10/2018.
//

import Foundation

public struct ZenIoC {
    
    fileprivate var factories = [String: Any]()
    
    public static var shared = ZenIoC()
    
    public mutating func register<T>(factory: @escaping () -> T) {
        let key = String(describing: T.self)
        factories[key] = factory
    }
    
    public func resolve<T>() -> T {
        let key = String(describing: T.self)
        if let factory = factories[key] as? () -> T {
            return factory()
        } else {
            fatalError("not found")
        }
    }
}
