//
//  Synchronized.swift
//  Customer.io
//
//  Created by Holly Schilling on 12/18/25.
//

import Dispatch

/// A wrapper for primitive types to make them thread safe and able to conform to `Sendable`.
public final class Synchronized<T>: @unchecked Sendable {
    
    public let syncQueue = DispatchQueue(label: "Synchronized \(String(describing: T.self))", attributes: .concurrent)
    private var _value: T
    public var value: T {
        get {
            return syncQueue.sync { _value }
        }
        set {
            syncQueue.sync(flags: .barrier) {
                _value = newValue
            }
        }
    }
    
    public init(initial: T) {
        _value = initial
    }
    
    /// Modify the value held in a thread-safe manor.
    /// - Parameters:
    ///  - body: The code to modify the value. It must return the updated value.
    public func mutating(_ body: (T) throws -> T) rethrows {
        try syncQueue.sync(flags: .barrier) {
            _value = try body(_value)
        }
    }
    
    /// Access the value held in a thread-safe manor.
    /// - Parameters:
    ///  - body: The code to modify the value. The return value is passed through and returned to the caller, leaving the original value unchanged.
    public func using<Result>(_ body: (T) throws -> Result) rethrows -> Result {
        return try syncQueue.sync {
            try body(_value)
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

extension Synchronized: AdditiveArithmetic where T: AdditiveArithmetic {
    
    public static var zero: Synchronized<T> {
        return Synchronized(initial: .zero)
    }
    
    public static prefix func + (input: Synchronized<T>) -> Synchronized<T> {
        return Synchronized(initial: input.value)
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
    
    public static func += (lhs: inout Synchronized<T>, rhs: Synchronized<T>) {
        lhs.mutating { lhsValue in
            rhs.using { rhsValue in
                lhsValue + rhsValue
            }
        }
    }

    public static func += (lhs: inout Synchronized<T>, rhs: T) {
        lhs.mutating { lhsValue in
            lhsValue + rhs
        }
    }

    public static func -= (lhs: inout Synchronized<T>, rhs: Synchronized<T>) {
        lhs.mutating { lhsValue in
            rhs.using { rhsValue in
                lhsValue - rhsValue
            }
        }
    }

    public static func -= (lhs: inout Synchronized<T>, rhs: T) {
        lhs.mutating { lhsValue in
            lhsValue - rhs
        }
    }

}
