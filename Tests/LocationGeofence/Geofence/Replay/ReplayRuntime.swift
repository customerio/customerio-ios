import Foundation

/// Whether this runtime can run the replay composition at all.
///
/// Not a static on `ReplayHarness`: that type is `@available(iOS 17.0, *)` and `@MainActor`, and a
/// `@Suite` trait is evaluated outside both contexts.
///
/// A trait rather than an availability attribute because Swift Testing refuses to attach a test to
/// an unavailable declaration, and so an older runtime reports these as **skipped** rather than
/// passing without asserting. Below iOS 17 is the classic monitor's path, tested elsewhere.
enum ReplayRuntime {
    static var isMonitorAvailable: Bool {
        if #available(iOS 17.0, *) { true } else { false }
    }
}
