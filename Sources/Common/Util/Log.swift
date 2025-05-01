import Foundation
#if canImport(os)
import os.log
#endif

/// mockable logger + abstract that allows you to log to multiple places if you wish
public protocol Logger: AutoMockable {
    /// Represents the current log level of the logger. The log level
    /// controls the verbosity of the logs that are output. Only messages
    /// at this level or higher will be logged.
    var logLevel: CioLogLevel { get }
    /// Sets the dispatcher to handle log events based on the log level.
    /// Default implementation is to print logs to XCode Debug Area.
    /// In wrapper SDKs, this will be overridden to emit logs to more user-friendly channels like console, etc.
    /// - Parameter dispatcher: Dispatcher to handle log events based on the log level, pass null to reset to default.
    func setLogDispatcher(_ dispatcher: ((CioLogLevel, String) -> Void)?)
    /// Sets the logger's verbosity level to control which messages are logged.
    /// Levels range from `.debug` (most verbose) to `.error` (least verbose).
    /// - Parameter level: The `CioLogLevel` for logging output verbosity.
    func setLogLevel(_ level: CioLogLevel)
    /// the noisey log level. Feel free to spam this log level with any
    /// information about the SDK that would be useful for debugging the SDK.
    func debug(_ message: String, _ tag: String?)
    /// Not noisy log messages. Good for general information such as
    /// when the background queue begins and ends running but use `debug`
    /// for the status of each background queue task running.
    func info(_ message: String, _ tag: String?)
    /// the SDK is in an unstable state that you want to notify
    /// the customer or our development team about.
    func error(_ message: String, _ tag: String?, _ throwable: Error?)
}

public extension Logger {
    func debug(_ message: String) {
        debug(message, nil)
    }

    func info(_ message: String) {
        info(message, nil)
    }

    func error(_ message: String) {
        error(message, nil, nil)
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

// log messages to console.
// sourcery: InjectRegisterShared = "Logger"
// sourcery: InjectSingleton
public class LoggerImpl: Logger {
    private let systemLogger: SystemLogger
    public var logLevel: CioLogLevel = .error

    init(logger: SystemLogger) {
        self.systemLogger = logger
    }

    public func setLogLevel(_ level: CioLogLevel) {
        logLevel = level
    }

    private var logDispatcher: ((CioLogLevel, String) -> Void)?

    public func setLogDispatcher(_ dispatcher: ((CioLogLevel, String) -> Void)?) {
        logDispatcher = dispatcher
    }

    public func debug(_ message: String, _ tag: String?) {
        printMessage(message, .debug, tag, nil)
    }

    public func info(_ message: String, _ tag: String? = nil) {
        printMessage("\(message)", .info, tag, nil)
    }

    public func error(_ message: String, _ tag: String?, _ error: Error?) {
        printMessage("\(message)", .error, tag, error)
    }

    private func printMessage(_ message: String, _ level: CioLogLevel, _ tag: String?, _ error: Error?) {
        if !logLevel.shouldLog(level) { return }

        let formattedMessage = formatMessage(message, tag, error)
        logDispatcher?(level, message) ?? systemLogger.log(formattedMessage, level)
    }

    private func formatMessage(_ message: String, _ tag: String? = nil, _ error: Error? = nil) -> String {
        var formatted = message

        if let tag = tag {
            formatted = "[\(tag)] \(formatted)"
        }

        if let error = error {
            formatted += " Error: \(error.localizedDescription)"
        }

        return formatted
    }
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
