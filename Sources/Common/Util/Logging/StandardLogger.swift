//
//  StandardLogger.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/10/25.
//

public class StandardLogger: Logger {

    public var outputter: LogOutputter
    public var logLevel: CioLogLevel = .error

    public init(logLevel: CioLogLevel = .error, outputter: LogOutputter = SystemLogOutputter()) {
        self.logLevel = logLevel
        self.outputter = outputter
    }

    public func setLogLevel(_ level: CioLogLevel) {
        logLevel = level
    }
    
    public func log(_ level: CioLogLevel, _ message: @autoclosure () -> String, _ tag: String?, context: (label: String, content: CustomStringConvertible)?) {
        guard logLevel.shouldLog(level) else {
            return
        }
        
        let formattedMessage = formatMessage(tag: tag, message: message(), context: context)
        outputter.output(level: level, formattedMessage)
    }
    
    private func formatMessage(tag: String? = nil, message: String, context: (label: String, content: CustomStringConvertible)?) -> String {

        var components: [String] = []
        
        if let tag {
            components.append("[\(tag)]")
        }
        components.append(message)
        if let context = context {
            components.append("\(context.label): \(context.content)")
        }
        let formatted = components.joined(separator: " ")
        return formatted
    }
}
