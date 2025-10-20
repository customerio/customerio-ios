import Foundation

/**
 Guarantee the wrapped value is only ever accessed from one thread at a time.

 Class is public because public fields may be Atomic.
 This class is only used for internal SDK development, only. It's not part of the official SDK.

 Inspired from: https://github.com/RougeWare/Swift-Atomic/blob/master/Sources/Atomic/Atomic.swift
 */
@propertyWrapper
public struct Atomic<DataType: Any> {
    fileprivate let exclusiveAccessQueue = DispatchQueue(label: "Atomic \(UUID())", qos: .userInteractive)

    // Use a class wrapper to avoid Swift's exclusivity checking on struct mutation
    fileprivate final class ValueBox {
        var value: DataType
        init(_ value: DataType) {
            self.value = value
        }
    }
    
    fileprivate let box: ValueBox

    /// Safely accesses the unsafe value from within the context of its exclusive-access queue
    public var wrappedValue: DataType {
        get { exclusiveAccessQueue.sync { box.value } }
        set { exclusiveAccessQueue.sync { box.value = newValue } }
    }

    /**
     Initializer that satisfies @propertyWrapper's requirements.
     With this initializer created, you can assign default values to our wrapped properties,
     like this: `@Atomic var foo = Foo()`
     */
    public init(wrappedValue: DataType) {
        self.box = ValueBox(wrappedValue)
    }
}
