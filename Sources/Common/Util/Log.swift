import Foundation
#if canImport(os)
import os.log
#endif

/// mockable logger + abstract that allows you to log to multiple places if you wish
public protocol Logger {
    /// Represents the current log level of the logger. The log level
    /// controls the verbosity of the logs that are output. Only messages
    /// at this level or higher will be logged.
    var logLevel: CioLogLevel { get }
    /// Sets the dispatcher to handle log events based on the log level.
    /// Default implementation is to print logs to XCode Debug Area.
    /// In wrapper SDKs, this will be overridden to emit logs to more user-friendly channels like console, etc.
    /// - Parameter dispatcher: Dispatcher to handle log events based on the log level, pass null to reset to default.
//    func setLogDispatcher(_ dispatcher: ((CioLogLevel, String) -> Void)?)
    /// Sets the logger's verbosity level to control which messages are logged.
    /// Levels range from `.debug` (most verbose) to `.error` (least verbose).
    /// - Parameter level: The `CioLogLevel` for logging output verbosity.
    func setLogLevel(_ level: CioLogLevel)

    /// Outputs a message to the log with the designated log level and optional tag.
    /// - Parameter level: The level the log message should be considered.
    /// - Parameter message: The message to log.
    /// - Parameter tag: A tag to include with the logged message to simplify filtering later.
    /// - Parameter context: An object that may help with debugging and a label to describe it. Most often, this content is a thrown object, like an error, but it can be anything useful.
    func log(_ level: CioLogLevel, _ message: @autoclosure () -> String, _ tag: String?, context: (label: String, content: CustomStringConvertible)?)
}

public extension Logger {

    /// Outputs a message to the log with the designated log level and optional tag.
    /// - Parameter level: The level the log message should be considered.
    /// - Parameter message: The message to log.
    /// - Parameter tag: A label to include with the logged message to simplify filtering later.
    func log(_ level: CioLogLevel, _ message: @autoclosure () -> String, _ tag: String? = nil) {
        log(level, message(), tag, context: nil)
    }

    
    /// the noisey log level. Feel free to spam this log level with any
    /// information about the SDK that would be useful for debugging the SDK.
    func debug(_ message: String, _ tag: String? = nil, context: (label: String, content: CustomStringConvertible)? = nil) {
        log(.debug, message, tag, context: context)
    }
    
    /// Not noisy log messages. Good for general information such as
    /// when the background queue begins and ends running but use `debug`
    /// for the status of each background queue task running.
    func info(_ message: String, _ tag: String? = nil, context: (label: String, content: CustomStringConvertible)? = nil) {
        log(.info, message, tag, context: context)
    }

    /// the SDK is in an unstable state that you want to notify
    /// the customer or our development team about.
    func error(_ message: String, _ tag: String? = nil, _ throwable: Error? = nil) {
        let context = throwable.map { (label: "Error", content: $0.localizedDescription) }
        log(.error, message, tag, context: context)
    }
}

/// none - no logs will be made
/// error - only log when there is an error in the SDK (default)
/// info - basic SDK informion. Somewhat noisy. Recommended to start debugging SDK.
/// debug - most noisy. See all of the logs made from the SDK.
public enum CioLogLevel: String, CaseIterable {
    case none
    case error
    case info
    case debug

    #if canImport(os)
    func shouldLog(_ level: CioLogLevel) -> Bool {
        switch self {
        case .none: return false
        case .error:
            return level == .error
        case .info:
            return level == .error || level == .info
        case .debug:
            return true
        }
    }

    var osLogLevel: OSLogType {
        switch self {
        case .none: return .info
        case .error: return .error
        case .info: return .info
        case .debug: return .debug
        }
    }
    #endif
}

public extension CioLogLevel {
    static func getLogLevel(for value: String) -> CioLogLevel? {
        switch value.lowercased() {
        case CioLogLevel.none.rawValue:
            return CioLogLevel.none
        case CioLogLevel.error.rawValue:
            return .error
        case CioLogLevel.info.rawValue:
            return .info
        case CioLogLevel.debug.rawValue:
            return .debug
        default:
            return nil
        }
    }
}

// log messages to console.
// sourcery: InjectRegisterShared = "Logger"
// sourcery: InjectSingleton
public class LoggerImpl: Logger {

    public var outputter: LogOutputter
    public var logLevel: CioLogLevel = .error

    init(outputter: LogOutputter = SystemLogOutputter()) {
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

