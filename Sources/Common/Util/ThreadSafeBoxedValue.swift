import Foundation

/// A lock-protected container for thread-safe mutable state.
///
/// **Common use cases:**
/// 1. **Thread-safe state in actors** - For `nonisolated` properties that need mutable state
/// 2. **Test mocks** - For tracking call counts and arguments from multiple threads
/// 3. **Bridging non-Sendable types** - For Objective-C types or legacy APIs
///
/// **Example:**
/// ```swift
/// actor MyActor {
///     private let counters = ThreadSafeBoxedValue((calls: 0, errors: 0))
///
///     nonisolated var callCount: Int { counters.withValue { $0.calls } }
///
///     func trackCall() {
///         counters.withValue { $0.calls += 1 }
///     }
/// }
/// ```
///
/// **Caveats:**
/// - The compiler cannot verify correctness. You are taking responsibility for safety.
/// - Every access is guarded by an `NSLock`, which may have performance costs.
/// - Avoid re-entrant access inside `withValue` closures, or you may deadlock.
///
/// Prefer `actor` for isolated state. Use this when you need `nonisolated` access or
/// cannot control the type's Sendability.
public final class ThreadSafeBoxedValue<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    public init(_ value: Value) {
        self.value = value
    }

    /// Safely access or mutate the wrapped value under a lock.
    public func withValue<T>(_ body: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
