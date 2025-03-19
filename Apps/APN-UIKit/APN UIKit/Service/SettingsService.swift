// sourcery: InjectRegisterShared = "SettingsService"
class SettingsService {
    private let storage: Storage

    init(storage: Storage) {
        self.storage = storage

        setDefaultSettings()
    }

    func setDefaultSettings(force: Bool = false) {
        guard force || storage.didSetDefaults == false else { return }

        storage.didSetDefaults = true
        storage.settings = Settings(
            dataPipelines: DataPipelinesSettings(
                cdpApiKey: BuildEnvironment.CustomerIO.cdpApiKey,
                siteId: BuildEnvironment.CustomerIO.siteId,
                region: .US,
                autoTrackDeviceAttributes: true,
                autoTrackUIKitScreenViews: true,
                trackApplicationLifecycleEvents: true,
                screenViewUse: .All,
                logLevel: .Error
            ),
            messaging: MessagingPushAPNSettings(
                autoFetchDeviceToken: true,
                autoTrackPushEvents: true,
                showPushAppInForeground: true
            ),
            inApp: MessagingInAppSettings(
                siteId: BuildEnvironment.CustomerIO.siteId,
                region: .US
            ),
            internalSettings: InternalSettings(
                cdnHost: "cdp.customer.io/v1",
                apiHost: "cdp.customer.io/v1",
                inAppEnvironment: .Production,
                testMode: true
            )
        )
    }
}
