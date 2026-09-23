import Foundation

/// Waits for detached work by its outcome, not by a fixed sleep: polls every 10 ms up to `timeout`.
///
/// The condition runs on whatever context the caller's task is on, which is deliberately *not* the
/// main actor — `GeofenceRefreshTriggerTests` and `InAppMessageStateTests` are not main-actor
/// isolated and poll plain values. A condition that touches `@MainActor` state needs `settleOnMain`
/// instead; reading it here tears the read rather than failing, and has killed the test process.
@discardableResult
func settle(timeout: TimeInterval = 2, until condition: @escaping () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        // Cancellation ends the wait rather than being swallowed. `try?` here would drop the
        // `CancellationError` and spin the loop at full speed for the rest of the timeout,
        // re-entering `condition()` — and through it the SDK — thousands of times.
        do {
            try await Task.sleep(nanoseconds: 10000000)
        } catch {
            return false
        }
    }
    return condition()
}

/// `settle`, for conditions that read main-actor state.
///
/// The condition is non-escaping and evaluated on the main actor, so a test can poll a `@MainActor`
/// OS double directly. Same polling interval and same return contract as `settle`.
@MainActor
@discardableResult
func settleOnMain(timeout: TimeInterval = 2, until condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        do {
            try await Task.sleep(nanoseconds: 10000000)
        } catch {
            return false
        }
    }
    return condition()
}

/// For assertions of absence: a bounded window for a stray call to land.
func settleQuietly(_ seconds: TimeInterval = 0.3) async {
    await Task.yield()
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1000000000))
}
