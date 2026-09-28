import CioInternalCommon
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The foreground re-evaluation pass, split from the resolver's core for the file cap. The members
/// it reads are `internal` only because of the split.
@MainActor
extension PolygonMembershipResolver {
    func registerForegroundEvaluation() {
        #if canImport(UIKit)
        foregroundObserverToken = notificationCenter.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Captured here because no caller supplies an expected user on this path, and the
                // pass usually suspends on a fix request (a foregrounding app's cached fix is stale).
                //
                // Signed out at both ends compares nil to nil and proceeds. Safe only because
                // sign-out clears `monitoredGeofenceIds`, so the pass finds no polygons.
                // Registering while signed out would break this.
                let expectedUserId = self.contextStore.currentUserId
                Task { [contextStore = self.contextStore] in
                    await self.evaluateAllPolygons(
                        reason: .foreground,
                        isStillCurrent: { contextStore.currentUserId == expectedUserId }
                    )
                }
            }
        }
        #endif
    }
}
