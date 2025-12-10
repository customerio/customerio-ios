//
//  AccumulatorLogOutputter.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/10/25.
//

import Dispatch

public class AccumulatorLogOutputter: LogOutputter {
    private var _messages: [(CioLogLevel, String)] = []
    
    public var messages: [(CioLogLevel, String)] {
        workQueue.sync {
            _messages
        }
    }
    
    private let workQueue = DispatchQueue(label: "io.customer.sdk.AccumulatorLogOutputter.workQueue")
    
    
    public var onMessageReceived: ((CioLogLevel, String) -> Void)?
    
    public var hasMessages: Bool {
        return workQueue.sync {
            !_messages.isEmpty
        }
    }
    
    public var debugMessages: [String] {
        return workQueue.sync {
            _messages.compactMap { ($0.0 == .debug) ? $0.1 : nil }
        }
    }
    
    public var firstDebugMessage: String? {
        return workQueue.sync {
            _messages.first(where: { $0.0 == .debug })?.1
        }
    }

    public var infoMessages: [String] {
        return workQueue.sync {
            _messages.compactMap { ($0.0 == .info) ? $0.1 : nil }
        }
    }

    public var firstInfoMessage: String? {
        return workQueue.sync {
            _messages.first(where: { $0.0 == .info })?.1
        }
    }

    public var errorMessages: [String] {
        return workQueue.sync {
            _messages.compactMap { ($0.0 == .error) ? $0.1 : nil }
        }
    }

    public var firstErrorMessage: String? {
        return workQueue.sync {
            _messages.first(where: { $0.0 == .error })?.1
        }
    }

    public func output(level: CioLogLevel, _ message: String) {
        workQueue.sync {
            _messages.append((level, message))
        }
        onMessageReceived?(level, message)
    }
    
    public func clear() {
        workQueue.sync {
            _messages.removeAll()
        }
    }
}

