import CioTracking
import Foundation

// Stores the settings that override behavior of the Customer.io SDK in the app.
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
            keyValueStorage.cioSettings
        }
        set {
            keyValueStorage.cioSettings = newValue
        }
    }
}
