import Foundation

/// Waits for detached work by its outcome, not by a fixed sleep: polls every 10 ms up to `timeout`.
@discardableResult
func settle(timeout: TimeInterval = 2, until condition: @escaping () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 10000000)
    }
    return condition()
}

/// For assertions of absence: a bounded window for a stray call to land.
func settleQuietly(_ seconds: TimeInterval = 0.3) async {
    await Task.yield()
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1000000000))
}
