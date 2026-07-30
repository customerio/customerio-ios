import CioInternalCommon
import Foundation

/// The SDK capabilities that the Live Activities module requires from the host SDK.
///
/// Declared as a protocol so the module can be tested without depending on the real
/// `CustomerIO.shared` singleton. Pass a conforming fake in unit tests; the default
/// (`CustomerIO.shared`) is used in production.
protocol CIOLiveActivitiesSDKProviding {
    var registeredDeviceToken: String? { get }
    /// Whether a user is currently identified. Backed by the data pipeline, which updates it
    /// synchronously during identify()/clearIdentify(), so it is accurate the instant those
    /// return — used to gate lifecycle events without racing an async identify().
    var isUserIdentified: Bool { get }
    var eventBusHandler: EventBusHandler { get }
    var logger: Logger { get }
    var sharedKeyValueStorage: SharedKeyValueStorage { get }
    func track(name: String, properties: [String: Any]?)
}

extension CustomerIO: CIOLiveActivitiesSDKProviding {
    var eventBusHandler: EventBusHandler {
        DIGraphShared.shared.eventBusHandler
    }

    var logger: Logger {
        DIGraphShared.shared.logger
    }

    var sharedKeyValueStorage: SharedKeyValueStorage {
        DIGraphShared.shared.sharedKeyValueStorage
    }

    // Reuses the DataPipelineTracking reverse-dependency (the same one the Location module
    // consumes) rather than reading analytics directly. Returns false when DataPipeline isn't
    // initialized. Its isUserIdentified is updated synchronously on identify()/clearIdentify().
    var isUserIdentified: Bool {
        DIGraphShared.shared.getOptional(DataPipelineTracking.self)?.isUserIdentified ?? false
    }

    // registeredDeviceToken is already declared on CustomerIO via CustomerIOInstance.
    // track(name:properties:) is also already on CustomerIO.
}
