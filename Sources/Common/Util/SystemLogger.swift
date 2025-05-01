import Foundation
#if canImport(os)
import os.log
#endif

public protocol SystemLogger: AutoMockable {
    func log(_ message: String, _ level: CioLogLevel)
}

// sourcery: InjectRegisterShared = "SystemLogger"
public class SystemLoggerImpl: SystemLogger {
    // allows filtering in Console mac app
    public let logSubsystem = "io.customer.sdk"
    public let logCategory = "CIO"

    public func log(_ message: String, _ level: CioLogLevel) {
        #if canImport(os)
        // Unified logging for Swift. https://www.avanderlee.com/workflow/oslog-unified-logging/
        // This means we can view logs in xcode console + Console app.
        if #available(iOS 14, *) {
            let logger = os.Logger(subsystem: logSubsystem, category: logCategory)
            logger.log(level: level.osLogLevel, "\(message, privacy: .public)")
        } else {
            let logger = OSLog(subsystem: logSubsystem, category: logCategory)
            os_log("%{public}@", log: logger, type: level.osLogLevel, message)
        }
        #else
        // At this time, Linux cannot use `os.log` or `OSLog`. Instead, use: https://github.com/apple/swift-log/
        // As we don't officially support Linux at this time, no need to add a dependency to the project.
        // therefore, we are not logging if can't import os.log
        #endif
    }
}
