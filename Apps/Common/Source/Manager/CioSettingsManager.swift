import CioTracking
import Foundation

public class CioSettingsManager {
    private let keyValueStorage: KeyValueStore = .init()

    public init() {}

    var hasAppSetSettings: Bool {
        keyValueStorage.cioSettings != nil
    }

    public func restoreSdkDefaultSettings() {
        appSetSettings = nil
    }

    public var appSetSettings: CioSettings? {
        get {
            if let appSetSettings = keyValueStorage.cioSettings {
                return appSetSettings
            }

            return nil
        }
        set {
            keyValueStorage.cioSettings = newValue
        }
    }

    public var settings: CioSettings {
        get {
            appSetSettings ?? CioSettings.getFromCioSdk()
        }
        set {
            keyValueStorage.cioSettings = newValue
        }
    }
}
