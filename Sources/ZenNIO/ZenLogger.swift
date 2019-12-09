//
//  ZenLogger.swift
//  
//
//  Created by Gerardo Grisolini on 08/12/2019.
//

import Foundation
import Logging


public enum Target {
    case console, file
}

/// Outputs logs to a `Console`.
public struct ZenLogger: LogHandler {
    private static let path: String = "\(FileManager.default.currentDirectoryPath)/logs"
    private static var fmtDay = DateFormatter()
    private static var fmt = DateFormatter()
    
    public let label: String

    /// See `LogHandler.metadata`.
    public var metadata: Logger.Metadata
    
    /// See `LogHandler.logLevel`.
    public var logLevel: Logger.Level
    
    /// The outputs that the messages will get logged to.
    public let logTargets: [Target]
    
    /// Creates a new `ZenLogger` instance.
    ///
    /// - Parameters:
    ///   - label: Unique identifier for this logger.
    ///   - targets: The outputs to log the messages to.
    ///   - level: The minimum level of message that the logger will output. This defaults to `.debug`, the lowest level.
    ///   - metadata: Extra metadata to log with the message. This defaults to an empty dictionary.
    public init(label: String, targets: [Target], level: Logger.Level = .debug, metadata: Logger.Metadata = [:]) {
        self.label = label
        self.metadata = metadata
        self.logLevel = level
        self.logTargets = targets
        
        ZenLogger.fmt.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZ"
        ZenLogger.fmt.locale = Locale.current
        ZenLogger.fmtDay.dateFormat = "yyyy-MM-dd"
        ZenLogger.fmtDay.locale = Locale.current
        
        var isFolder = ObjCBool(true)
        if targets.contains(.file) && !FileManager.default.fileExists(atPath: ZenLogger.path, isDirectory: &isFolder) {
            do {
                try FileManager.default.createDirectory(atPath: ZenLogger.path, withIntermediateDirectories: true, attributes: nil)
            } catch {
                debugPrint("Logs \(ZenLogger.path): \(error.localizedDescription)")
                return
            }
        }
        debugPrint("Logs: \(ZenLogger.path)")
    }
        
    /// See `LogHandler[metadataKey:]`.
    ///
    /// This just acts as a getter/setter for the `.metadata` property.
    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { return self.metadata[key] }
        set { self.metadata[key] = newValue }
    }
    
    /// See `LogHandler.log(level:message:metadata:file:function:line:)`.
    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        file: String,
        function: String,
        line: UInt
    ) {
        var text: String = ""
        
        if self.logLevel <= .trace {
            text += "[ \(self.label) ] "
        }
            
        text += "[ \(level.name) ] \(message.description)"
        
        // only log metadata + file info if we are debug or trace
        if self.logLevel <= .debug {
            if !self.metadata.isEmpty {
                // only log metadata if not empty
                text += " " + self.metadata.description
            }
            // log the concise path + line
            let fileInfo = self.conciseSourcePath(file) + ":" + line.description
            text += " (" + fileInfo + ")"
        }
        
        if logTargets.contains(.console) {
            print(text)
        }
        
        if logTargets.contains(.file) {
            self.writeToFile(text)
        }
    }
    
    /// splits a path on the /Sources/ folder, returning everything after
    ///
    ///     "/Users/developer/dev/MyApp/Sources/Run/main.swift"
    ///     // becomes
    ///     "Run/main.swift"
    ///
    private func conciseSourcePath(_ path: String) -> String {
        return path.split(separator: "/")
            .split(separator: "Sources")
            .last?
            .joined(separator: "/") ?? path
    }
    

    private func writeToFile(_ message: String) {
        let date = Date()
        let logFile = "\(ZenLogger.path)/\(ZenLogger.fmtDay.string(from: date)).log"
        if !FileManager.default.fileExists(atPath: logFile) {
            guard FileManager.default.createFile(atPath: logFile, contents: nil, attributes: nil) == true else {
                return
            }
        }
        
        guard let data = "\(ZenLogger.fmt.string(from: date)) \(message)\n".data(using: .utf8) else {
            return
        }

        if let fileHandle = FileHandle(forWritingAtPath: logFile) {
            defer {
                fileHandle.closeFile()
            }
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
        }
    }
    
    public static func setTimezone(secondsFromGMT: Int) {
        ZenLogger.fmt.timeZone = TimeZone(secondsFromGMT: secondsFromGMT)
        ZenLogger.fmtDay.timeZone = TimeZone(secondsFromGMT: secondsFromGMT)
    }

    public static var file: String {
        return "\(ZenLogger.path)/\(ZenLogger.fmtDay.string(from: Date())).log"
    }
    
    public static var data: Data? {
        if let fileHandle = FileHandle(forReadingAtPath: ZenLogger.file) {
            defer {
                fileHandle.closeFile()
            }
            return fileHandle.readDataToEndOfFile()
        }
        return nil
    }
}

extension LoggingSystem {
    /// Bootstraps a `ZenLogger` to the `LoggingSystem`, so that logger will be used in `Logger.init(label:)`.
    ///
    ///     LoggingSystem.boostrap(console: console)
    ///
    /// - Parameters:
    ///   - targets: The output the logger will log the messages to.
    ///   - level: The minimum level of message that the logger will output. This defaults to `.debug`, the lowest level.
    ///   - metadata: Extra metadata to log with the message. This defaults to an empty dictionary.
    public static func bootstrap(targets: [Target], level: Logger.Level = .info, metadata: Logger.Metadata = [:]) {
        self.bootstrap { label in
            return ZenLogger(label: label, targets: targets, level: level, metadata: metadata)
        }
    }
}

extension Logger.Level {
    public var name: String {
        switch self {
        case .trace: return "TRACE"
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        case .critical: return "CRITICAL"
        }
    }
}
