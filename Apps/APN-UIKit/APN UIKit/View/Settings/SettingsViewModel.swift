class SettingsViewModel {
    var settings: Settings!
    private let storage = DIGraphShared.shared.storage
    weak var settingsRouter: SettingsRouter?

    init(settingRouter: SettingsRouter) {
        self.settingsRouter = settingRouter

        setLocalSettings()
    }

    func overrideSiteIdAndCdpApiKey(siteIdOverride: String?, cdpApiKeyOverride: String?) {
        if let siteIdOverride {
            settings.dataPipelines.siteId = siteIdOverride
            settings.inApp.siteId = siteIdOverride
        }
        if let cdpApiKeyOverride {
            settings.dataPipelines.cdpApiKey = cdpApiKeyOverride
        }
    }

    // MARK: Routing

    func internalSettingsScreenRequested() {
        settingsRouter?.routeToInternalSettings()
    }

    // MARK: Main Settings

    // -- Data Pipelines

    func cdpApiKeyUpdated(_ value: String) {
        settings.dataPipelines.cdpApiKey = value
    }

    func sideIdUpdated(_ value: String) {
        settings.dataPipelines.siteId = value
    }

    func regionUpdated(_ value: Region) {
        settings.dataPipelines.region = value
    }

    func autoTrackDeviceAttributesUpdated(_ value: Bool) {
        settings.dataPipelines.autoTrackDeviceAttributes = value
    }

    func autoTrackUIKitScreenViewsUpdated(_ value: Bool) {
        settings.dataPipelines.autoTrackUIKitScreenViews = value
    }

    func trackApplicationLifecycleEventsUpdated(_ value: Bool) {
        settings.dataPipelines.trackApplicationLifecycleEvents = value
    }

    func screenViewUseUpdted(_ value: ScreenViewUse) {
        settings.dataPipelines.screenViewUse = value
    }

    func logLevelUpdated(_ value: LogLevel) {
        settings.dataPipelines.logLevel = value
    }

    // -- Messaging Push APN

    func autoFetchDeviceTokenUpdated(_ value: Bool) {
        settings.messaging.autoFetchDeviceToken = value
    }

    func autoTrackPushEventsUpdated(_ value: Bool) {
        settings.messaging.autoTrackPushEvents = value
    }

    func showPushAppInForegroundUpdated(_ value: Bool) {
        settings.messaging.showPushAppInForeground = value
    }

    // -- Messaging In App

    func inAppSideIdUpdated(_ siteId: String) {
        settings.inApp.siteId = siteId
    }

    func inAppRegionUpdated(_ region: Region) {
        settings.inApp.region = region
    }

    // -- Actions

    func saveSettings() {
        storage.settings = settings
    }

    func restoreDefaultSettings() {
        DIGraphShared.shared.settingsService.setDefaultSettings(force: true)

        setLocalSettings()
    }

    // MARK: Internal Settings

    func cdnHostUpdated(_ cdnHost: String) {
        settings.internalSettings.cdnHost = cdnHost
    }

    func apiHostUpdated(_ apiHost: String) {
        settings.internalSettings.apiHost = apiHost
    }

    func testModeUpdated(_ testMode: Bool) {
        settings.internalSettings.testMode = testMode
    }

    // MARK: Private

    private func setLocalSettings() {
        guard let storageSettings = DIGraphShared.shared.storage.settings else {
            fatalError("Failed to load settings from storage")
        }
        settings = storageSettings
    }
}
