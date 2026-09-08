import CioInternalCommon
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// The foreground re-evaluation pass, split from the resolver's core so both stay under the file
/// cap. The members it reads are `internal` rather than `private` only because of this split; they
/// remain implementation detail of an internal type.
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
                // Sampled here, not read at emit time: the pass resolves a fix first, and a
                // foregrounding app's cached fix is normally stale — the app was suspended — so
                // that request really does suspend. No caller supplies an expected user on this
                // path, so the observer takes its own.
                //
                // Anonymous at both ends compares nil to nil and proceeds; that is safe only
                // because a signed-out process has no `monitoredGeofenceIds`, so the pass returns
                // empty before it resolves anything. Registration while anonymous would break it.
                let expectedUserId = self.contextStore.currentUserId
                Task { [contextStore = self.contextStore] in
                    await self.evaluateAllPolygons(
                        isStillCurrent: { contextStore.currentUserId == expectedUserId }
                    )
                }
            }
        }
        #endif
    }
}
