import CioInternalCommon
import Foundation
#if canImport(UIKit)
import UIKit
#endif

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
                // Signed out at both ends compares nil to nil and proceeds; safe only because
                // sign-out clears `monitoredGeofenceIds`.
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
