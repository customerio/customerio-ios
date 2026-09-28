import Foundation

/// Not on `ReplayHarness`: a `@Suite` trait is evaluated outside its `@available` and `@MainActor`
/// contexts. A trait, so older runtimes report skipped rather than passing without asserting.
enum ReplayRuntime {
    static var isMonitorAvailable: Bool {
        if #available(iOS 17.0, *) { true } else { false }
    }
}
