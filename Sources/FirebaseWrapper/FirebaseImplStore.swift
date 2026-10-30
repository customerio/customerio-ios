import CioInternalCommon
import Foundation

/// Keeps one Firebase adapter for the app.
///
/// `MessagingPushFCM.initialize(withConfig:)` may run more than once. A new adapter would drop work queued before
/// `FirebaseApp.configure()`, and would wrap the previous adapter's delegate interposer, which is released with it,
/// cutting the app's own MessagingDelegate out of Firebase's callbacks.
enum FirebaseImplStore {
    private static let current = Synchronized<FirebaseImpl?>(nil)

    /// The app's adapter, created with `makeAdapter` on first use.
    static func adapter(makeAdapter: () -> FirebaseImpl) -> FirebaseImpl {
        current.mutating { adapter in
            if let adapter = adapter {
                return adapter
            }
            let newAdapter = makeAdapter()
            adapter = newAdapter
            return newAdapter
        }
    }

    /// Forgets the adapter. Tests only.
    static func reset() {
        current.wrappedValue = nil
    }
}
