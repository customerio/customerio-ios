import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Lifecycle wakes and the re-arm they trigger, split from the evidence scheduling so both stay
/// under the file cap.
extension GeofenceDwellCoordinator {
    func registerForegroundEvaluation() {
        #if canImport(UIKit)
        observeLifecycle(UIApplication.willEnterForegroundNotification) { coordinator in
            // First: a visit recorded in the background under foreground-only access ends here,
            // before the re-arm requests evidence for it.
            coordinator.foregroundChanged()
            coordinator.recordWake(.wakeForeground)
            coordinator.taskSpawner.spawn { await coordinator.rearmPendingEvidence(includePolygons: true) }
        }
        observeLifecycle(UIApplication.didEnterBackgroundNotification) { $0.foregroundChanged() }
        observeLifecycle(UIApplication.backgroundRefreshStatusDidChangeNotification) { coordinator in
            coordinator.backgroundRefreshChanged()
        }
        #endif
    }

    private func observeLifecycle(
        _ name: Notification.Name,
        _ handle: @escaping @MainActor (GeofenceDwellCoordinator) -> Void
    ) {
        lifecycleObservers.append(notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handle(self)
            }
        })
    }

    /// Records a wake as the OS delivers it, before any task: recorded later, it could follow an
    /// identity clear and take the next user's token. Signed out, no visit is pending to wake.
    func recordWake(_ wake: DwellDiagnosticEvent, fenceId: String? = nil) {
        guard let userId = contextStore.currentUserId, !userId.isEmpty else { return }
        recordDiagnostic(wake, fenceId: fenceId)
    }

    /// Re-arms every pending visit's deadline from its elapsed time. The visit's dwell-proof budget
    /// and spacing are persisted on it, so a re-arm neither replenishes nor shortens them.
    ///
    /// A deadline is an in-process sleep: it does not run while the app is suspended, and may run
    /// late after one. So besides foregrounding, every background wake the SDK gets — a region
    /// callback, a CLVisit — calls this, and a visit that came due while suspended requests its
    /// evidence then. That is the best iOS allows; nothing here emits on elapsed time alone.
    ///
    /// Re-arming rather than requesting now: a due visit still requests once its spacing allows,
    /// but pre-threshold evidence cannot qualify and would spend the bounded budget.
    ///
    /// - Parameter includePolygons: false on a background wake. A polygon's evidence is a forced
    ///   fresh-fix pass, and the wake's own pass is already one; a second concurrent one is
    ///   answered with the same fix, refused as an echo, and decides nothing for either.
    func rearmPendingEvidence(includePolygons: Bool) async {
        guard let userId = contextStore.currentUserId, !userId.isEmpty else { return }
        let geofences = await storage.getCachedGeofences().filter { geofence in
            geofence.dwellThresholdSeconds > 0 && (includePolygons || geofence.vertices == nil)
        }
        for geofence in geofences {
            guard let visit = await currentVisit(geofence: geofence, userId: userId), !visit.emitted,
                  // A newer visit's own deadline, scheduled while the read above was suspended,
                  // must not be replaced by this older read.
                  (evidenceRetries[geofence.id]?.visitId ?? visit.visitId) == visit.visitId
            else { continue }
            scheduleDeadline(for: geofence, visit: visit)
        }
    }
}
