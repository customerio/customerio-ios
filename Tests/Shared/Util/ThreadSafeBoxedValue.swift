import Foundation

/// Lock-protected container for thread-safe mutable state in test mocks and stubs.
///
/// Enables Swift 6 compliant state tracking across multiple threads in tests.
public final class ThreadSafeBoxedValue<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    public init(_ value: Value) {
        self.value = value
    }

    /// Access or mutate the wrapped value under a lock.
    public func withValue<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
