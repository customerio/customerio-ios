//
//  SettingsViewModel.swift
//  APN UIKit
//
//  Created by Uros Milivojevic on 17.3.25..
//

class SettingsViewModel {
    var settings: Settings
    private let storage = DIGraphShared.shared.storage
    weak var settingsRouter: SettingsRouter?
        
    
    init(settingRouter: SettingsRouter) {
        self.settingsRouter = settingRouter
        
        guard let storageSettings = DIGraphShared.shared.storage.settings else {
            fatalError("Failed to load settings from storage")
        }
        self.settings = storageSettings
    }
    
    // MARK: Routing
    
    func internalSettingsScreenRequested() {
        settingsRouter?.routeToInternalSettings()
    }
   
    // MARK: Data updates
    // -- Data Pipelines
    
    func cdpApiKeyUpdated(_ cdpApiKey: String) {
        settings.dataPipelines.cdpApiKey = cdpApiKey
        storage.settings = settings
    }
    
    func sideIdUpdated(_ siteId: String) {
        settings.dataPipelines.siteId = siteId
        storage.settings = settings
    }

    func regionUpdated(_ region: Region) {
        settings.dataPipelines.region = region
        storage.settings = settings
    }
    
    func autoTrackDeviceAttributesUpdated(_ value: Bool) {
        settings.dataPipelines.autoTrackDeviceAttributes = value
        storage.settings = settings
    }
    
    func autoTrackUIKitScreenViewsUpdated(_ value: Bool) {
        settings.dataPipelines.autoTrackUIKitScreenViews = value
        storage.settings = settings
    }
    
    func trackApplicationLifecycleEventsUpdated(_ value: Bool) {
        settings.dataPipelines.trackApplicationLifecycleEvents = value
        storage.settings = settings
    }
    
    func screenViewUseUpdted(_ value: ScreenViewUse) {
        settings.dataPipelines.screenViewUse = value
        storage.settings = settings
    }
    
    func logLevelUpdated(_ value: LogLevel) {
        settings.dataPipelines.logLevel = value
        storage.settings = settings
    }

    // -- Messaging Push APN
    
    func autoFetchDeviceTokenUpdated(_ value: Bool) {
        settings.messaging.autoFetchDeviceToken = value
        storage.settings = settings
    }
    
    func autoTrackPushEventsUpdated(_ value: Bool) {
        settings.messaging.autoTrackPushEvents = value
        storage.settings = settings
    }
    
    func showPushAppInForegroundUpdated(_ value: Bool) {
        settings.messaging.showPushAppInForeground = value
        storage.settings = settings
    }

    // -- Messaging In App
    
    func inAppSideIdUpdated(_ siteId: String) {
        settings.inApp.siteId = siteId
    }
    
    func inAppRegionUpdated(_ region: Region) {
        settings.inApp.region = region
        storage.settings = settings
    }

    // -- Internal Settings
    
    func cdnHostUpdated(_ cdnHost: String) {
        settings.internalSettings.cdnHost = cdnHost
        storage.settings = settings
    }
    
    func apiHostUpdated(_ apiHost: String) {
        settings.internalSettings.apiHost = apiHost
        storage.settings = settings
    }
    
    func testModeUpdated(_ testMode: Bool) {
        settings.internalSettings.testMode = testMode
        storage.settings = settings
    }
    
    func restoreDefaultInternalSettings() {
        settings.internalSettings = DIGraphShared.shared.settingsService.defaultInternalSettings
        storage.settings = settings
    }
    
}
