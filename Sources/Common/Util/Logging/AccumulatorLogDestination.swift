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
public class AccumulatorLogDestination: LogDestination {
    
    public init() { }
    
    private var _allMessages: [LogMessage] = []
    
    /// Returns all messages that have been received, ordered as they arrived
    public var allMessages: [LogMessage] {
        workQueue.sync {
            _allMessages
        }
    }
    
    private let workQueue = DispatchQueue(
        label: "io.customer.sdk.AccumulatorLogDestination.workQueue",
        attributes: .concurrent
    )
    
    /// A callback for being notified that a message has been received.
    /// When set, this callback is performed on the calling thread but
    /// outside of the serialized callback paths. As a result, this callback
    /// will block the current thread, but does not block other threads from
    /// utilizing this AccumulatorLogDestination or its associated Logger.
    public var onMessageReceived: ((LogMessage) -> Void)?
    
    /// Checks if the AccumulatorLogDestination has received any messages.
    /// This property is shorthand for `!allMessages.isEmpty`
    public var hasMessages: Bool {
        return workQueue.sync {
            !_allMessages.isEmpty
        }
    }
    
    /// Returns all messages that have been received that are at exactly the debug level.
    /// This is a computed property used by filtering `allMessages`, so caching the result
    /// is preferred to computing it repeatedly.
    public var debugMessages: [LogMessage] {
        return workQueue.sync {
            _allMessages.filter { ($0.level == .debug) }
        }
    }
    
    /// Returns the first message in received that is at exactly the debug level.
    /// This is computed and a shorthand for
    /// `allMessages.first { $0.level == .debug }`
    public var firstDebugMessage: LogMessage? {
        return workQueue.sync {
            _allMessages.first { $0.level == .debug }
        }
    }

    /// Returns all messages that have been received that are at exactly the info level.
    /// This is a computed property used by filtering `allMessages`, so caching the result
    /// is preferred to computing it repeatedly.
    public var infoMessages: [LogMessage] {
        return workQueue.sync {
            _allMessages.filter { ($0.level == .info) }
        }
    }

    /// Returns the first message in received that is at exactly the info level.
    /// This is computed and a shorthand for
    /// `allMessages.first { $0.level == .info }`
    public var firstInfoMessage: LogMessage? {
        return workQueue.sync {
            _allMessages.first { $0.level == .info }
        }
    }

    /// Returns all messages that have been received that are at exactly the error level.
    /// This is a computed property used by filtering `allMessages`, so caching the result
    /// is preferred to computing it repeatedly.
    public var errorMessages: [LogMessage] {
        return workQueue.sync {
            _allMessages.filter { ($0.level == .error) }
        }
    }

    /// Returns the first message in received that is at exactly the error level.
    /// This is computed and a shorthand for
    /// `allMessages.first { $0.level == .error }`
    public var firstErrorMessage: LogMessage? {
        return workQueue.sync {
            _allMessages.first { $0.level == .error }
        }
    }

    public func output(message: LogMessage) {
        workQueue.sync(flags: .barrier) {
            _allMessages.append(message)
        }
        onMessageReceived?(message)
    }
    
    /// Erase all log messages received.
    public func clear() {
        workQueue.sync(flags: .barrier) {
            _allMessages.removeAll()
        }
    }
}

