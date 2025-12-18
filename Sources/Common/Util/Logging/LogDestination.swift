//
//  LogDestination.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/9/25.
//

import Foundation

public struct LogMessage: Sendable {
    var timestamp: Date
    var level: CioLogLevel
    var tag: String?
    var content: String
    
    public init(level: CioLogLevel, content: String, tag: String? = nil, timestamp: Date = Date()) {
        self.level = level
        self.content = content
        self.tag = tag
        self.timestamp = timestamp
    }
    
}

/// The protocol for receiving output from the Logger. The most common destination is the console,
/// handled by `ConsoleLogDestination`. Alternatively, messages can be routed to the
/// system log by `SystemLogDestination`. If the logs should be completely thrown out,
/// `NullLogDestination` can be used. Other possible implementations could include things
/// like writing logs in SQLite or sending them over a network to a remote endpoint. 
///
public protocol LogDestination: Sendable {
    func output(message: LogMessage)
}
