public protocol SdkInitializationLogger: AutoMockable {
    func coreSdkInitStart()
    func coreSdkInitSuccess()
    func moduleInitStart(_ moduleName: String)
    func moduleInitSuccess(_ moduleName: String)
}

// sourcery: InjectRegisterShared = "SdkInitializationLogger"
public class SdkInitializationLoggerImpl: SdkInitializationLogger {
    private static let TAG = "Init"

    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    public func coreSdkInitStart() {
        logger.debug("Creating new instance of CustomerIO SDK version: \(SdkVersion.version)...", Self.TAG)
    }

    public func coreSdkInitSuccess() {
        logger.info("CustomerIO SDK is initialized and ready to use", Self.TAG)
    }

    public func moduleInitStart(_ moduleName: String) {
        logger.debug("Initializing SDK module \(moduleName)...", Self.TAG)
    }

    public func moduleInitSuccess(_ moduleName: String) {
        logger.info("CustomerIO \(moduleName) module is initialized and ready to use", Self.TAG)
    }
}
