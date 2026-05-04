import Dispatch
import Foundation

/// A wrapper for primitive types to make them thread safe and able to conform to `Sendable`.
public final class Synchronized<T>: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var _wrappedValue: T
    public var wrappedValue: T {
        get {
            lock.withLock {
                _wrappedValue
            }
        }
        set {
            lock.withLock {
                _wrappedValue = newValue
            }
        }
    }

    public init(_ initial: T) {
        self._wrappedValue = initial
    }

    /// Modify the wrapped value in a thread-safe manor.
    /// - Parameters:
    /// - body: The critical section of code that may modify the wrapped value.
    /// - Returns: The value returned from the inner function.
    public func mutating<Result>(_ body: (inout T) throws -> Result) rethrows -> Result {
        try lock.withLock {
            try body(&_wrappedValue)
        }
    }

    /// Modify the wrapped value in a thread-safe manor without blocking the current thread but
    /// asynchronously waiting for it to finish. The body will be executed atomically before the call returns.
    public func mutatingAsync<Result>(
        _ body: @Sendable (inout T) throws -> sending Result
    ) async throws -> Result {
        try await withoutActuallyEscaping(body) { escapingBody in
            try await withUnsafeThrowingContinuation { continuation in
                Task.detached {
                    let result = Swift.Result {
                        try self.lock.withLock {
                            try escapingBody(&self._wrappedValue)
                        }
                    }
                    continuation.resume(with: result)
                }
            }
        }
    }

    /// Modify the wrapped value in a thread-safe manor without blocking the current thread but
    /// asynchronously waiting for it to finish. The body will be executed atomically before the call returns.
    public func mutatingAsync<Result>(
        _ body: @Sendable (inout T) -> sending Result
    ) async -> sending Result {
        await withoutActuallyEscaping(body) { escapingBody in
            await withUnsafeContinuation { continuation in
                Task.detached {
                    let result = self.lock.withLock {
                        escapingBody(&self._wrappedValue)
                    }
                    continuation.resume(returning: result)
                }
            }
        }
    }

    /// Access the wrapped value in a thread-safe manor.
    /// - Parameters:
    ///  - body: The code to access the wrapped value. The return value is passed through and returned to the caller, leaving the original value unchanged.
    public func using<Result>(_ body: (T) throws -> Result) rethrows -> Result {
        try lock.withLock {
            try body(_wrappedValue)
        }
    }

    /// Access the wrapped value in a thread-safe manor without blocking the current thread but
    /// asynchronously waiting for it to finish. The body will be executed atomically before the call returns.
    public func usingAsync<Result>(
        _ body: @Sendable (T) throws -> sending Result
    ) async throws -> sending Result {
        try await withoutActuallyEscaping(body) { escapingBody in
            try await withUnsafeThrowingContinuation { continuation in
                Task.detached {
                    let result = Swift.Result {
                        try self.lock.withLock {
                            try escapingBody(self._wrappedValue)
                        }
                    }
                    continuation.resume(with: result)
                }
            }
        }
    }

    /// Modify the wrapped value in a thread-safe manor without blocking the current thread but
    /// asynchronously waiting for it to finish. The body will be executed atomically before the call returns.
    public func usingAsync<Result>(
        _ body: @Sendable (T) -> sending Result
    ) async -> sending Result {
        await withoutActuallyEscaping(body) { escapingBody in
            await withUnsafeContinuation { continuation in
                Task.detached {
                    let result = self.lock.withLock {
                        escapingBody(self._wrappedValue)
                    }
                    continuation.resume(returning: result)
                }
            }
        }
    }
    
    /// Sets a new value while returning the old one in one atomic operation..
    public func atomicSetAndFetch(_ newValue: T) -> T {
        mutating {
            let oldValue = $0
            $0 = newValue
            return oldValue
        }
    }
}
