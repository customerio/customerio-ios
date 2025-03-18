// sourcery: InjectRegisterShared = "SettingsService"
class SettingsService {
    private let storage: Storage
    let defaultInternalSettings: InternalSettings

    init(storage: Storage) {
        self.storage = storage

        self.defaultInternalSettings = InternalSettings(
            cdnHost: "cdp.customer.io/v1",
            apiHost: "cdp.customer.io/v1",
            inAppEnvironment: .Production,
            testMode: true
        )

        setDefaultSettings()
    }

    func setDefaultSettings() {
        guard storage.didSetDefaults == false else { return }

        let settings = Settings(
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
            internalSettings: defaultInternalSettings
        )

        storage.settings = settings
    }

//    func setDefaultInternalSettings() {
//        guard var settings = storage.settings else { return }
//        settings.internalSettings = defaultInternalSettings
//        self.storage.settings = settings
//    }
}
