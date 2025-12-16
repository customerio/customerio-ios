//
//  StandardLogger.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/10/25.
//

public class StandardLogger: Logger {

    public var destination: LogDestination
    public var logLevel: CioLogLevel = .error

    public init(logLevel: CioLogLevel = .error, destination: LogDestination = ConsoleLogDestination()) {
        self.logLevel = logLevel
        self.destination = destination
    }

    public func setLogLevel(_ level: CioLogLevel) {
        logLevel = level
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
