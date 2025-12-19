import CioInternalCommon

protocol DataPipelinesLogger: Sendable, AutoMockable {
    func logStoringDevicePushToken(token: String, userId: String?)
    func logStoringBlankPushToken()
    func logRegisteringPushToken(token: String, userId: String?)
    func logPushTokenRefreshed()
    func automaticTokenRegistrationForNewProfile(token: String, userId: String)
    func logDeletingTokenDueToNewProfileIdentification()
    func logTrackingDevicesAttributesWithoutValidToken()
}

// sourcery: InjectRegisterShared = "DataPipelinesLogger"
struct DataPipelinesLoggerImpl: DataPipelinesLogger {

    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    public func logStoringDevicePushToken(token: String, userId: String?) {
        logger.debug("Storing device token: \(token) for user profile: \(userId ?? "nil")", Tags.Push)
    }

    public func logStoringBlankPushToken() {
        logger.debug("Attempting to register blank token, ignoring request", Tags.Push)
    }

    public func logRegisteringPushToken(token: String, userId: String?) {
        logger.debug("Registering device token: \(token) for user profile: \(userId ?? "nil")", Tags.Push)
    }

    public func logPushTokenRefreshed() {
        logger.debug("Token refreshed, deleting old token to avoid registering same device multiple times", Tags.Push)
    }

    public func automaticTokenRegistrationForNewProfile(token: String, userId: String) {
        logger.debug("Automatically registering device token: \(token) to newly identified profile: \(userId)", Tags.Push)
    }

    public func logDeletingTokenDueToNewProfileIdentification() {
        logger.debug("Deleting device token before identifying new profile", Tags.Push)
    }

    public func logTrackingDevicesAttributesWithoutValidToken() {
        logger.debug("No device token found. ignoring request to track device attributes", Tags.Push)
    }
}
