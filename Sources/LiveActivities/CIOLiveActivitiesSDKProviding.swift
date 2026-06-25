import CioInternalCommon
import Foundation

/// The SDK capabilities that `LiveActivitiesModule` requires from the host SDK.
///
/// Declared as a protocol so the module can be tested without depending on the real
/// `CustomerIO.shared` singleton. Pass a conforming mock in unit tests; the default
/// (`CustomerIO.shared`) is used in production.
protocol CIOLiveActivitiesSDKProviding {
    var installationId: String { get }
    var registeredDeviceToken: String? { get }
    var eventBusHandler: EventBusHandler { get }
    var logger: Logger { get }
    var storageManager: StorageManager? { get }
    func track(name: String, properties: [String: Any]?)
}

extension CustomerIO: CIOLiveActivitiesSDKProviding {
    var eventBusHandler: EventBusHandler {
        DIGraphShared.shared.eventBusHandler
    }

    var logger: Logger {
        DIGraphShared.shared.logger
    }

    var storageManager: StorageManager? {
        DIGraphShared.shared.storageManager
    }

    // installationId and registeredDeviceToken are already declared on CustomerIO
    // via CustomerIOInstance. track(name:properties:) is also already on CustomerIO.
}
