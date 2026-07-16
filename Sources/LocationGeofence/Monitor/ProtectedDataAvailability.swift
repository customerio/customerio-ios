import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Whether the device's file-protected storage is currently readable. `CLMonitor` loads its
/// persisted conditions from the app container, so it must not be created before first unlock on a
/// reboot cold-wake — that state would be unavailable. Injected so the deferral is testable.
@MainActor
protocol ProtectedDataAvailability: AnyObject {
    var isAvailable: Bool { get }
    /// Returns once protected data is readable — immediately if it already is, otherwise when the
    /// system next reports availability.
    func waitUntilAvailable() async
}

/// Production `ProtectedDataAvailability` backed by `UIApplication`.
@MainActor
final class UIApplicationProtectedDataAvailability: ProtectedDataAvailability {
    var isAvailable: Bool {
        UIApplication.shared.isProtectedDataAvailable
    }

    func waitUntilAvailable() async {
        if isAvailable { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            var token: NSObjectProtocol?
            let finish = {
                guard !resumed else { return }
                resumed = true
                if let token { NotificationCenter.default.removeObserver(token) }
                continuation.resume()
            }
            token = NotificationCenter.default.addObserver(
                forName: UIApplication.protectedDataDidBecomeAvailableNotification,
                object: nil,
                queue: .main
            ) { _ in MainActor.assumeIsolated { finish() } }
            // Close the check-then-register race: availability may have flipped in between.
            if isAvailable { finish() }
        }
    }
}
