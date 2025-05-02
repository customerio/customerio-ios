// sourcery: InjectRegisterShared = "SdkInitializationLogger"
// sourcery: InjectSingleton
public class SdkInitializationLogger {
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

    func moduleInitStart(_ moduleName: String) {
        logger.debug("Initializing SDK module \(moduleName)...", Self.TAG)
    }

    func moduleInitSuccess(_ moduleName: String) {
        logger.info("CustomerIO \(moduleName) module is initialized and ready to use", Self.TAG)
    }
}
