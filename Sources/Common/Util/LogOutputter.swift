//
//  LogOutputter.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/9/25.
//

import Foundation
#if canImport(os)
import os.log
#endif

public protocol LogOutputter {
    func output(level: CioLogLevel, _ message: String)
}

public struct SystemLogOutputter: LogOutputter {
    // allows filtering in Console mac app
    public let logSubsystem = "io.customer.sdk"
    public let logCategory = "CIO"

    public func output(level: CioLogLevel, _ message: String) {
#if canImport(os)
        // Unified logging for Swift. https://www.avanderlee.com/workflow/oslog-unified-logging/
        // This means we can view logs in xcode console + Console app.
        if #available(iOS 14, *) {
            let logger = os.Logger(subsystem: logSubsystem, category: logCategory)
            logger.log(level: level.osLogLevel, "\(message, privacy: .public)")
        } else {
            let logger = OSLog(subsystem: logSubsystem, category: logCategory)
            os_log("%{public}@", log: logger, type: level.osLogLevel, message)
        }
#else
        // At this time, Linux cannot use `os.log` or `OSLog`. Instead, use: https://github.com/apple/swift-log/
        // As we don't officially support Linux at this time, no need to add a dependency to the project.
        // therefore, we are not logging if can't import os.log
#endif

    }
}

public struct ConsoleLogOutputter: LogOutputter {
    public func output(level: CioLogLevel, _ message: String) {
        Swift.print("[\(level)] \(message)")
    }
}

public class AccumulatorLogOutputter: LogOutputter {
    public private(set) var messages: [(CioLogLevel, String)] = []
    
    public var onMessageReceived: ((CioLogLevel, String) -> Void)?
    
    public var hasMessages: Bool {
        return !messages.isEmpty
    }
    
    public var debugMessages: [String] {
        return messages.compactMap { ($0.0 == .debug) ? $0.1 : nil }
    }
    
    public var firstDebugMessage: String? {
        return messages.first(where: { $0.0 == .debug })?.1
    }

    public var infoMessages: [String] {
        return messages.compactMap { ($0.0 == .info) ? $0.1 : nil }
    }

    public var firstInfoMessage: String? {
        return messages.first(where: { $0.0 == .info })?.1
    }

    public var errorMessages: [String] {
        return messages.compactMap { ($0.0 == .error) ? $0.1 : nil }
    }

    public var firstErrorMessage: String? {
        return messages.first(where: { $0.0 == .error })?.1
    }

    public func output(level: CioLogLevel, _ message: String) {
        messages.append((level, message))
        onMessageReceived?(level, message)
    }
    
    public func clear() {
        messages.removeAll()
    }
}

