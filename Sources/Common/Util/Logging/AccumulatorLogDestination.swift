//
//  AccumulatorLogDestination.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/10/25.
//

import Dispatch

/// A LogDestination that keeps messages in memory and makes them able to
/// be easily parsed through by the application. Requests are all serialized,
/// which makes this LogDestination potentially slower than others. Use of this
/// LogDestination is intended for testing purposes only.
public final class AccumulatorLogDestination: LogDestination {
    
    public init() { }
    
    private let _allMessages: Synchronized<[LogMessage]> = Synchronized(initial: [])
    
    /// Returns all messages that have been received, ordered as they arrived
    public var allMessages: [LogMessage] {
        _allMessages.wrappedValue
    }
    
    private let workQueue = DispatchQueue(
        label: "io.customer.sdk.AccumulatorLogDestination.workQueue",
        attributes: .concurrent
    )
    
    /// Checks if the AccumulatorLogDestination has received any messages.
    /// This property is shorthand for `!allMessages.isEmpty`
    public var hasMessages: Bool {
        !_allMessages.wrappedValue.isEmpty
    }
    
    /// Returns all messages that have been received that are at exactly the debug level.
    /// This is a computed property used by filtering `allMessages`, so caching the result
    /// is preferred to computing it repeatedly.
    public var debugMessages: [LogMessage] {
        _allMessages.wrappedValue.filter { ($0.level == .debug) }
    }
    
    /// Returns the first message in received that is at exactly the debug level.
    /// This is computed and a shorthand for
    /// `allMessages.first { $0.level == .debug }`
    public var firstDebugMessage: LogMessage? {
        _allMessages.wrappedValue.first { $0.level == .debug }
    }

    /// Returns all messages that have been received that are at exactly the info level.
    /// This is a computed property used by filtering `allMessages`, so caching the result
    /// is preferred to computing it repeatedly.
    public var infoMessages: [LogMessage] {
        _allMessages.wrappedValue.filter { ($0.level == .info) }
    }

    /// Returns the first message in received that is at exactly the info level.
    /// This is computed and a shorthand for
    /// `allMessages.first { $0.level == .info }`
    public var firstInfoMessage: LogMessage? {
        _allMessages.wrappedValue.first { $0.level == .info }
    }

    /// Returns all messages that have been received that are at exactly the error level.
    /// This is a computed property used by filtering `allMessages`, so caching the result
    /// is preferred to computing it repeatedly.
    public var errorMessages: [LogMessage] {
        _allMessages.wrappedValue.filter { ($0.level == .error) }
    }

    /// Returns the first message in received that is at exactly the error level.
    /// This is computed and a shorthand for
    /// `allMessages.first { $0.level == .error }`
    public var firstErrorMessage: LogMessage? {
        _allMessages.wrappedValue.first { $0.level == .error }
    }

    public func output(message: LogMessage) {
        _allMessages.append(message)
    }
    
    /// Erase all log messages received.
    public func clear() {
        _allMessages.removeAll()
    }
}

