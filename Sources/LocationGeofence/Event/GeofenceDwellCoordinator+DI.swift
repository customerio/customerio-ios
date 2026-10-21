import CioInternalCommon
import Foundation
#if canImport(UIKit)
import UIKit
#endif

extension DIGraphShared {
    @MainActor
    var geofenceDwellCoordinator: GeofenceDwellCoordinator {
        let overridden: GeofenceDwellCoordinator? = getOverriddenInstance()
        return overridden ?? GeofenceDwellCoordinator.shared
    }
}

extension GeofenceDwellCoordinator {
    @MainActor
    static let shared = GeofenceDwellCoordinator(
        storage: DIGraphShared.shared.geofenceStorage,
        transitionEmitter: DIGraphShared.shared.geofenceEventTracker,
        contextStore: DIGraphShared.shared.backgroundDeliveryContextStore,
        logger: DIGraphShared.shared.logger,
        locationAccess: { DIGraphShared.shared.geofenceMonitor.locationAccess },
        backgroundRefreshAvailable: {
            #if canImport(UIKit)
            UIApplication.shared.backgroundRefreshStatus == .available
            #else
            true
            #endif
        },
        identityTracker: DIGraphShared.shared.geofenceIdentityTracker,
        // Info.plist, so a background launch that never initializes the SDK sees the same opt-in.
        pendingDwellCollection: PendingDwellCollectionOwner.ifOptedIn(PendingDwellCollectionOptIn(bundle: .main)),
        diagnosticRecorder: DIGraphShared.shared.dwellDiagnosticRecorder
    )
}
