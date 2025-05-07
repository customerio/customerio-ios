import CioInternalCommon

protocol DataPipelinesLogger: AutoMockable {
    func logStoringDevicePushToken(token: String, userId: String?)
    func logStoringBlankPushToken()
    func logRegisteringPushToken(token: String, userId: String?)
    func logPushTokenRefreshed()
}

// sourcery: InjectRegisterShared = "DataPipelinesLogger"
class DataPipelinesLoggerImpl: DataPipelinesLogger {
    private static let PUSH_TAG = "Push"

    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    public func logStoringDevicePushToken(token: String, userId: String?) {
        logger.debug("Storing device token: \(token) for user profile: \(userId ?? "nil")", Self.PUSH_TAG)
    }

    public func logStoringBlankPushToken() {
        logger.debug("Attempting to register blank token, ignoring request", Self.PUSH_TAG)
    }

    public func logRegisteringPushToken(token: String, userId: String?) {
        logger.debug("Registering device token: \(token) for user profile: \(userId ?? "nil")", Self.PUSH_TAG)
    }

    public func logPushTokenRefreshed() {
        logger.debug("Token refreshed, deleting old token to avoid registering same device multiple times", Self.PUSH_TAG)
    }
}
