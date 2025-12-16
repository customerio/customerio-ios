//
//  ConsoleLogDestination.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/10/25.
//

import Foundation

public struct ConsoleLogDestination: LogDestination {
    
    public init() { }

    /// A prefix to include on all messages. Omitted if nil (default).
    /// This is similar in function to the `tag` property on `LogMessage`, except
    /// that it is applied to all messages. This can be useful for separating console text
    /// from multiple sources. For example, setting this value to `"[CIO]"` could
    /// separate output sent by the Customer.IO Frameworks from that of the native app.
    public var prefix: String? = nil
    
    /// A date formatter to be used for formatting the date before printing it.
    /// If this value is nil, the date is omitted from the console output. By default
    /// this value is nil and the date is omitted.
    public var dateFormatter: DateFormatter?
    
    /// Outputs the provided LogMessage to the console.
    /// The components are output in this order:
    /// - prefix (if `prefix` is non-nil)
    /// - date (if `dateFormatter` is non-nil)
    /// - level
    /// - tag (if `message.tag` is set)
    /// - content
    public func output(message: LogMessage) {
        var components = [String]()
        if let prefix = prefix {
            components.append(prefix)
        }
        if let dateFormatter {
            let dateString = dateFormatter.string(from: message.timestamp)
            components.append(dateString)
        }
        components.append("[\(message.level.rawValue)]")
        
        if let tag = message.tag {
            components.append("[\(tag)]")
        }
        components.append(message.content)
        
        let result = components.joined(separator: " ")
        print(result)
    }
}
