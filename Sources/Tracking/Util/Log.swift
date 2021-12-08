import Foundation
#if canImport(os)
import os.log
#endif

/// mockable logger + abstract that allows you to log to multiple places if you wish
public protocol Logger: AutoMockable {
    /// the noisey log level. Feel free to spam this log level with any
    /// information about the SDK that would be useful for debugging the SDK.
    func debug(_ message: String)
    /// Not noisy log messages. Good for general information such as
    /// when the background queue begins and ends running but use `debug`
    /// for the status of each background queue task running.
    func info(_ message: String)
    /// the SDK is in an unstable state that you want to notify
    /// the customer or our development team about.
    func error(_ message: String)
}

// log messages to console.
// sourcery: InjectRegister = "Logger"
public class ConsoleLogger: Logger {
    // allows filtering in Console mac app
    private let logSubsystem = "io.customer.sdk"
    private let logCategory = "CIO"

    #if canImport(os)
    // Unified logging for Swift. https://www.avanderlee.com/workflow/oslog-unified-logging/
    // This means we can view logs in xcode console + Console app.
    private func printMessage(_ message: String, _ level: OSLogType) {
        if #available(iOS 14, *) {
            let logger = os.Logger(subsystem: self.logSubsystem, category: self.logCategory)
            logger.info("\(message, privacy: .public)")
        } else {
            let logger = OSLog(subsystem: logSubsystem, category: logCategory)
            os_log("%{public}@", log: logger, type: .info, message)
        }
    }

    public func debug(_ message: String) {
        printMessage(message, .debug)
    }

    public func info(_ message: String) {
        printMessage(message, .info)
    }

    public func error(_ message: String) {
        printMessage(message, .error)
    }
    #else
    // At this time, Linux cannot use `os.log` or `OSLog`. Instead, use: https://github.com/apple/swift-log/
    // As we don't officially support Linux at this time, no need to add a dependency to the project.
    // therefore, we are not logging if can't import os.log
    public func debug(_ message: String) {}
    public func info(_ message: String) {}
    public func error(_ message: String) {}
    #endif
}
