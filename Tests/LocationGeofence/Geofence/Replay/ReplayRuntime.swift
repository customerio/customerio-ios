import Foundation

/// Whether this runtime can run the replay composition at all.
///
/// A plain enum rather than a static on `ReplayHarness`, and deliberately so: the harness is
/// `@available(iOS 17.0, *)` and `@MainActor`, so a `@Suite` trait cannot reference anything on it
/// — the trait is evaluated outside both contexts. This type has neither annotation, which is the
/// whole reason it exists.
///
/// Expressed as a trait rather than an availability attribute because Swift Testing refuses to
/// attach a suite or test to an unavailable declaration, and expressed at all rather than left
/// implicit so an older runtime reports these as **skipped** rather than passing without asserting.
/// Nothing is lost below iOS 17: that is the classic monitor's path, which has its own tests and
/// never reaches this composition.
enum ReplayRuntime {
    static var isMonitorAvailable: Bool {
        if #available(iOS 17.0, *) { true } else { false }
    }
}
