import Foundation

/// Not main-actor: a condition reading `@MainActor` state must use `settleOnMain`, or it can crash.
@discardableResult
func settle(timeout: TimeInterval = 2, until condition: @escaping () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        // Not `try?`: swallowing cancellation would busy-spin until the timeout.
        do {
            try await Task.sleep(nanoseconds: 10000000)
        } catch {
            return false
        }
    }
    return condition()
}

/// `settle` for conditions that read main-actor state.
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

/// For asserting absence: gives a stray call time to land.
func settleQuietly(_ seconds: TimeInterval = 0.3) async {
    await Task.yield()
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1000000000))
}
