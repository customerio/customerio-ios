import CioInternalCommon
import Foundation

/// The SDK capabilities that the Live Activities module requires from the host SDK.
///
/// Declared as a protocol so the module can be tested without depending on the real
/// `CustomerIO.shared` singleton. Pass a conforming fake in unit tests; the default
/// (`CustomerIO.shared`) is used in production.
protocol CIOLiveActivitiesSDKProviding {
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

    // registeredDeviceToken is already declared on CustomerIO via CustomerIOInstance.
    // track(name:properties:) is also already on CustomerIO.
}
