import Dispatch
import Foundation

/// A wrapper for primitive types to make them thread safe and able to conform to `Sendable`.
public final class Synchronized<T>: @unchecked Sendable {
    public let syncQueue: DispatchQueue
    private var _wrappedValue: T
    public var wrappedValue: T {
        get {
            syncQueue.sync { _wrappedValue }
        }
        set {
            syncQueue.sync(flags: .barrier) {
                _wrappedValue = newValue
            }
        }
    }

    public init(initial: T, allowConcurrentReads: Bool = true) {
        self._wrappedValue = initial
        self.syncQueue = DispatchQueue(
            label: "Synchronized \(String(describing: T.self))",
            attributes: allowConcurrentReads ? .concurrent : []
        )
    }

    /// Modify the wrapped value in a thread-safe manor.
    /// - Parameters:
    /// - body: The critical section of code that may modify the wrapped value.
    /// - Returns: The value returned from the inner function.
    public func mutating<Result>(_ body: (inout T) throws -> Result) rethrows -> Result {
        try syncQueue.sync(flags: .barrier) {
            try body(&_wrappedValue)
        }
    }

    /// Modify the wrapped value in a thread-safe manor without blocking the current thread or
    /// waiting for it to finish. No guarantees are made about when the body will be executed,
    /// only that the body will be executed atomically.
    public func mutatingDetatched(_ body: @Sendable @escaping (inout T) -> Void) {
        syncQueue.async(flags: .barrier) {
            body(&self._wrappedValue)
        }
    }

    /// Modify the wrapped value in a thread-safe manor without blocking the current thread but
    /// asynchronously waiting for it to finish. The body will be executed atomically before the call returns.
    public func mutatingAsync<Result>(_ body: @Sendable @escaping (inout T) throws -> Result) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            syncQueue.async(flags: .barrier) {
                do {
                    let result = try body(&self._wrappedValue)
                    Task.detached {
                        continuation.resume(returning: result)
                    }
                } catch {
                    Task.detached {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    /// Access the wrapped value in a thread-safe manor.
    /// - Parameters:
    ///  - body: The code to access the wrapped value. The return value is passed through and returned to the caller, leaving the original value unchanged.
    public func using<Result>(_ body: (T) throws -> Result) rethrows -> Result {
        try syncQueue.sync {
            try body(_wrappedValue)
        }
    }

    /// Access the wrapped value in a thread-safe manor without blocking the current thread or
    /// waiting for it to finish. No guarantees are made about when the body will be executed,
    /// only that the body will be executed atomically.
    /// - Parameters:
    ///  - body: The code to access the wrapped value.
    public func usingDetatched(_ body: @Sendable @escaping (T) -> Void) {
        syncQueue.async {
            body(self._wrappedValue)
        }
    }

    /// Access the wrapped value in a thread-safe manor without blocking the current thread but
    /// asynchronously waiting for it to finish. The body will be executed atomically before the call returns.
    public func usingAsync<Result>(_ body: @Sendable @escaping (T) throws -> Result) async throws -> Result {
        try await withCheckedThrowingContinuation { continuation in
            syncQueue.async {
                do {
                    let result = try body(self._wrappedValue)
                    Task.detached {
                        continuation.resume(returning: result)
                    }
                } catch {
                    Task.detached {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}

extension Synchronized: Equatable where T: Equatable {
    public static func == (lhs: Synchronized<T>, rhs: Synchronized<T>) -> Bool {
        lhs.using { lhsValue in
            rhs.using { rhsValue in
                lhsValue == rhsValue
            }
        }
    }
}

extension Synchronized: Comparable where T: Comparable {
    public static func < (lhs: Synchronized<T>, rhs: Synchronized<T>) -> Bool {
        lhs.using { lhsValue in
            rhs.using { rhsValue in
                lhsValue < rhsValue
            }
        }
    }
}

extension Synchronized: Hashable where T: Hashable {
    public func hash(into hasher: inout Hasher) {
        using { value in
            value.hash(into: &hasher)
        }
    }
}

public extension Synchronized where T: AdditiveArithmetic {
    static var zero: Synchronized<T> {
        Synchronized(initial: .zero)
    }

    static prefix func + (input: Synchronized<T>) -> Synchronized<T> {
        input
    }

    static func + (lhs: Synchronized<T>, rhs: Synchronized<T>) -> T {
        lhs.using { lhsValue in
            rhs.using { rhsValue in
                lhsValue + rhsValue
            }
        }
    }

    static func + (lhs: Synchronized<T>, rhs: T) -> T {
        lhs.using { lhsValue in
            lhsValue + rhs
        }
    }

    static func - (lhs: Synchronized<T>, rhs: Synchronized<T>) -> T {
        lhs.using { lhsValue in
            rhs.using { rhsValue in
                lhsValue - rhsValue
            }
        }
    }

    static func - (lhs: Synchronized<T>, rhs: T) -> T {
        lhs.using { lhsValue in
            lhsValue - rhs
        }
    }

    static func += (lhs: Synchronized<T>, rhs: Synchronized<T>) {
        lhs.mutating { lhsValue in
            rhs.using { rhsValue in
                lhsValue += rhsValue
            }
        }
    }

    static func += (lhs: Synchronized<T>, rhs: T) {
        lhs.mutating { lhsValue in
            lhsValue += rhs
        }
    }

    static func -= (lhs: Synchronized<T>, rhs: Synchronized<T>) {
        lhs.mutating { lhsValue in
            rhs.using { rhsValue in
                lhsValue -= rhsValue
            }
        }
    }

    static func -= (lhs: Synchronized<T>, rhs: T) {
        lhs.mutating { lhsValue in
            lhsValue -= rhs
        }
    }
}

public protocol DictionaryProtocol {
    associatedtype Key: Hashable
    associatedtype Value

    subscript(key: Key) -> Value? { get set }
    mutating func removeValue(forKey key: Key) -> Value?
}

extension Dictionary: DictionaryProtocol {}

extension Synchronized: DictionaryProtocol where T: DictionaryProtocol {
    public typealias Key = T.Key
    public typealias Value = T.Value

    public subscript(key: Key) -> Value? {
        get {
            using { value in
                value[key]
            }
        }
        set {
            mutating { value in
                value[key] = newValue
            }
        }
    }

    @discardableResult
    public func removeValue(forKey key: Key) -> Value? {
        var result: Value?
        mutating { value in
            result = value.removeValue(forKey: key)
        }
        return result
    }
}

public extension Synchronized where T: Collection {
    subscript(key: T.Index) -> T.Element {
        using { value in
            value[key]
        }
    }

    var count: Int {
        using { value in value.count }
    }

    var isEmpty: Bool {
        using { value in value.isEmpty }
    }
}

public extension Synchronized where T: MutableCollection {
    subscript(position: T.Index) -> T.Element {
        get {
            using { value in
                value[position]
            }
        }
        set {
            mutating { value in
                value[position] = newValue
            }
        }
    }
}

public extension Synchronized where T: RangeReplaceableCollection {
    static func += <S>(lhs: inout Synchronized<T>, rhs: S) where S: Sequence, T.Element == S.Element {
        lhs.append(contentsOf: rhs)
    }

    static func += (lhs: inout Synchronized<T>, rhs: T.Element) {
        lhs.append(rhs)
    }

    func append(_ newElement: T.Element) {
        mutating { value in
            value.append(newElement)
        }
    }

    func append<S>(contentsOf newElements: S) where S: Sequence, T.Element == S.Element {
        mutating { value in
            value.append(contentsOf: newElements)
        }
    }

    func insert(_ newElement: T.Element, at i: T.Index) {
        mutating { value in
            value.insert(newElement, at: i)
        }
    }

    func insert<S>(contentsOf newElements: S, at i: T.Index) where S: Collection, T.Element == S.Element {
        mutating { value in
            value.insert(contentsOf: newElements, at: i)
        }
    }

    func removeAll(keepingCapacity keepCapacity: Bool = false) {
        mutating { value in
            value.removeAll(keepingCapacity: keepCapacity)
        }
    }
}
