import CioInternalCommon
import Foundation

/// The SDK capabilities that `LiveActivitiesModule` requires from the host SDK.
///
/// Declared as a protocol so the module can be tested without depending on the real
/// `CustomerIO.shared` singleton. Pass a conforming mock in unit tests; the default
/// (`CustomerIO.shared`) is used in production.
public protocol CIOLiveActivitiesSDKProviding {
    var installationId: String { get }
    var eventBusHandler: EventBusHandler { get }
    var logger: Logger { get }
}

extension CustomerIO: CIOLiveActivitiesSDKProviding {
    public var eventBusHandler: EventBusHandler {
        DIGraphShared.shared.eventBusHandler
    }

    public var logger: Logger {
        DIGraphShared.shared.logger
    }

    // installationId is already declared on CustomerIO via CustomerIOInstance.
}
