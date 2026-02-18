import Foundation

/// An object that manages the execution of tasks atomically.
/// Thread-safe wrapper for read/write access to a value using concurrent queue with barriers.
public struct Synchronized<Value> {
    private let mutex = DispatchQueue(label: "io.customer.SDK.Utils.Synchronized", attributes: .concurrent)
    private var _value: Value

    public init(_ value: Value) {
        self._value = value
    }

    /// Returns the thread-safe value.
    public var value: Value { mutex.sync { _value } }

    /// Submits a block for synchronous, thread-safe execution with write access.
    public mutating func value<T>(execute task: (inout Value) throws -> T) rethrows -> T {
        try mutex.sync(flags: .barrier) { try task(&_value) }
    }
}
