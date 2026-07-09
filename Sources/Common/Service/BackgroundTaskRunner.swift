import Foundation

/// Requests extra background execution time so a short async unit of work can finish after the OS
/// wakes the app briefly, instead of the app being suspended mid-flight. The assertion is released
/// when the work returns or the OS expires it, whichever comes first.
///
/// Best-effort timeliness aid only — callers must not depend on it for correctness. No-op where
/// `UIApplication` is unavailable (non-UIKit platforms, app extensions).
public protocol BackgroundTaskRunner: Sendable {
    func withBackgroundTime(_ work: @Sendable () async -> Void) async
}

/// No-op runner: runs the work inline, identical to not requesting background time. Default where
/// `UIApplication` is unavailable, and in tests.
public struct NoBackgroundTaskRunner: BackgroundTaskRunner {
    public init() {}

    public func withBackgroundTime(_ work: @Sendable () async -> Void) async {
        await work()
    }
}

#if canImport(UIKit)
import UIKit

/// Wraps `work` in a `UIApplication` background-task assertion. Unavailable in app extensions —
/// `UIApplication.shared` is a main-app-only API.
@available(iOSApplicationExtension, unavailable)
public struct UIKitBackgroundTaskRunner: BackgroundTaskRunner {
    /// Debug label for the assertion, shown in the debugger/Instruments. Each subsystem passes its
    /// own (e.g. geofence vs push delivery) so tasks are distinguishable in traces.
    private let name: String

    public init(name: String) {
        self.name = name
    }

    public func withBackgroundTime(_ work: @Sendable () async -> Void) async {
        let assertion = BackgroundTaskAssertion()
        await assertion.begin(name: name)
        await work()
        await assertion.end()
    }
}

/// Holds the assertion id on the main actor so the normal completion path and the OS expiration
/// handler both end it exactly once.
@available(iOSApplicationExtension, unavailable)
@MainActor
private final class BackgroundTaskAssertion {
    private var id: UIBackgroundTaskIdentifier = .invalid

    nonisolated init() {}

    func begin(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // OS is out of patience — end synchronously (this runs on the main thread) so the app
            // isn't killed by the watchdog. In-flight work is abandoned; the caller owns any retry.
            self?.end()
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
#endif
