import Foundation

/**
 Guarantee the wrapped value is only ever accessed from one thread at a time.
 Inspired from: https://github.com/RougeWare/Swift-Atomic/blob/master/Sources/Atomic/Atomic.swift
 */
@propertyWrapper
public struct Atomic<DataType: Any> {
    fileprivate let exclusiveAccessQueue = DispatchQueue(label: "Atomic \(UUID())", qos: .userInteractive)

    fileprivate var unsafeValue: DataType

    /// Safely accesses the unsafe value from within the context of its exclusive-access queue
    public var wrappedValue: DataType {
        get { exclusiveAccessQueue.sync { unsafeValue } }
        set { exclusiveAccessQueue.sync { unsafeValue = newValue } }
    }

    public init(wrappedValue: DataType) {
        self.unsafeValue = wrappedValue
    }
}
