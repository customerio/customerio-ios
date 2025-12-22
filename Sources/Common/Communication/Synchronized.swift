//
//  Synchronized.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/18/25.
//

import Foundation
import Dispatch

/// A wrapper for primitive types to make them thread safe and able to conform to `Sendable`.
public final class Synchronized<T>: @unchecked Sendable {
    
    public let syncQueue = DispatchQueue(label: "Synchronized \(String(describing: T.self))", attributes: .concurrent)
    private var _wrappedValue: T
    public var wrappedValue: T {
        get {
            return syncQueue.sync { _wrappedValue }
        }
        set {
            syncQueue.sync(flags: .barrier) {
                _wrappedValue = newValue
            }
        }
    }
    
    public init(initial: T) {
        _wrappedValue = initial
    }
    
    /// Modify the value held in a thread-safe manor.
    public func mutating(_ body: (inout T) throws -> Void) rethrows {
        try syncQueue.sync(flags: .barrier) {
            try body(&_wrappedValue)
        }
    }
    
    /// Asynchronously modify the value held in a thread-safe manor. No guarantees are made about
    /// when the mutation will be performed, only that it will be done safely.
    public func mutatingAsync(_ body: @Sendable @escaping (inout T) -> Void) {
        syncQueue.async(flags: .barrier) {
            body(&self._wrappedValue)
        }
    }
    
    
    /// Access the value held in a thread-safe manor.
    /// - Parameters:
    ///  - body: The code to modify the value. The return value is passed through and returned to the caller, leaving the original value unchanged.
    public func using<Result>(_ body: (T) throws -> Result) rethrows -> Result {
        return try syncQueue.sync {
            try body(_wrappedValue)
        }
    }
    
    /// Access the value held in a thread-safe manor. No guarantees are made about when the code will
    /// be performed, only that it will be done safely.
    /// - Parameters:
    ///  - body: The code to modify the value. The return value is passed through and returned to the caller, leaving the original value unchanged.
    public func usingAsync(_ body: @Sendable @escaping(T) -> Void) {
        syncQueue.async {
            body(self._wrappedValue)
        }
    }
}

extension Synchronized: Equatable where T: Equatable {
    public static func == (lhs: Synchronized<T>, rhs: Synchronized<T>) -> Bool {
        return lhs.using { lhsValue in
            rhs.using { rhsValue in
                lhsValue == rhsValue
            }
        }
    }
}

extension Synchronized: Comparable where T: Comparable {
    public static func < (lhs: Synchronized<T>, rhs: Synchronized<T>) -> Bool {
        return lhs.using { lhsValue in
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

extension Synchronized where T: AdditiveArithmetic {
    
    public static var zero: Synchronized<T> {
        return Synchronized(initial: .zero)
    }
    
    public static prefix func + (input: Synchronized<T>) -> Synchronized<T> {
        return Synchronized(initial: input.wrappedValue)
    }
    
    public static func + (lhs: Synchronized<T>, rhs: Synchronized<T>) -> Synchronized<T> {
        return Synchronized(
            initial: lhs.using { lhsValue in
                rhs.using { rhsValue in
                    lhsValue + rhsValue
                }
            }
        )
    }
    
    public static func - (lhs: Synchronized<T>, rhs: Synchronized<T>) -> Synchronized<T> {
        return Synchronized(
            initial: lhs.using { lhsValue in
                rhs.using { rhsValue in
                    lhsValue - rhsValue
                }
            }
        )
    }
    
    public static func += (lhs: Synchronized<T>, rhs: Synchronized<T>) {
        lhs.mutating { lhsValue in
            rhs.using { rhsValue in
                lhsValue += rhsValue
            }
        }
    }

    public static func += (lhs: Synchronized<T>, rhs: T) {
        lhs.mutating { lhsValue in
            lhsValue += rhs
        }
    }

    public static func -= (lhs: Synchronized<T>, rhs: Synchronized<T>) {
        lhs.mutating { lhsValue in
            rhs.using { rhsValue in
                lhsValue -= rhsValue
            }
        }
    }

    public static func -= (lhs: Synchronized<T>, rhs: T) {
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

extension Dictionary: DictionaryProtocol { }

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
        var result: Value? = nil
        mutating { value in
            result = value.removeValue(forKey: key)
        }
        return result
    }
}

extension Synchronized where T: Collection {
    
    public subscript(key: T.Index) -> T.Element {
        get {
            using { value in
                value[key]
            }
        }
    }
}

extension Synchronized where T: MutableCollection {
    
    public subscript(position: T.Index) -> T.Element {
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

extension Synchronized where T: RangeReplaceableCollection {
    
    public static func += <S>(lhs: inout Synchronized<T>, rhs: S) where S: Sequence, T.Element == S.Element {
        lhs.append(contentsOf: rhs)
    }

    public static func += (lhs: inout Synchronized<T>, rhs: T.Element) {
        lhs.append(rhs)
    }

    public func append(_ newElement: T.Element) {
        mutating { value in
            value.append(newElement)
        }
    }

    public func append<S>(contentsOf newElements: S) where S : Sequence, T.Element == S.Element {
        mutating { value in
            value.append(contentsOf: newElements)
        }
    }
    
    public func insert(_ newElement: T.Element, at i: T.Index) {
        mutating { value in
            value.insert(newElement, at: i)
        }
    }
    
    public func insert<S>(contentsOf newElements: S, at i: T.Index) where S : Collection, T.Element == S.Element {
        mutating { value in
            value.insert(contentsOf: newElements, at: i)
        }
    }
    
    public func removeAll(keepingCapacity keepCapacity: Bool = false) {
        mutating { value in
            value.removeAll(keepingCapacity: keepCapacity)
        }
    }
}
