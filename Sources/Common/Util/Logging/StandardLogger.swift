//
//  StandardLogger.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/10/25.
//

public final class StandardLogger: Logger {

    public let destination: LogDestination

    private let _logLevel: Synchronized<CioLogLevel>
    public var logLevel: CioLogLevel {
        get {
            _logLevel.value
        }
        set {
            _logLevel.value = newValue
        }
    }

    public init(logLevel: CioLogLevel = .error, destination: LogDestination = ConsoleLogDestination()) {
        _logLevel = Synchronized(initial: logLevel)
        self.destination = destination
    }

    public func setLogLevel(_ level: CioLogLevel) {
        _logLevel.value = level
    }
    
    public func log(_ level: CioLogLevel, _ message: @autoclosure () -> String, _ tag: String?, context: (label: String, content: CustomStringConvertible)?) {
        guard logLevel.shouldLog(level) else {
            return
        }
        
        let formatted = format(message: message(), context: context)
        let logMessage = LogMessage(level: level, content: formatted, tag: tag)
        
        destination.output(message: logMessage)
    }
    
    private func format(message: String, context: (label: String, content: CustomStringConvertible)?) -> String {

        var components: [String] = []
        
        components.append(message)
        if let context = context {
            components.append("\(context.label): \(context.content)")
        }
        let formatted = components.joined(separator: " ")
        return formatted
    }
}
