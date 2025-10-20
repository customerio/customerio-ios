import Foundation

public struct EnhancedSynchronized<Value>: @unchecked Sendable {
    private let queue: DispatchQueue
    
    // Use a class wrapper to avoid needing 'mutating' on methods
    // Mark as @unchecked Sendable since access is protected by the queue
    private final class ValueBox: @unchecked Sendable {
        var value: Value
        init(_ value: Value) {
            self.value = value
        }
    }
    
    private let box: ValueBox

    /**
     Initialize with a value and optional custom queue label.

     - Parameter initialValue: The initial value to store
     - Parameter label: Optional custom label for the dispatch queue (useful for debugging)
     */
    public init(_ initialValue: Value, label: String? = nil) {
        self.box = ValueBox(initialValue)
        self.queue = DispatchQueue(
            label: label ?? "io.customer.EnhancedSynchronized.\(UUID())",
            attributes: .concurrent
        )
    }

    public func get() -> Value {
        queue.sync { box.value }
    }

    public func set(_ newValue: Value) {
        queue.sync(flags: .barrier) {
            box.value = newValue
        }
    }

    /**
     Perform an atomic mutation on the value.

     The closure receives an inout reference to the value and can modify it safely.
     The entire operation is atomic - no other thread can read or write during the mutation.

     - Parameter mutation: Closure that modifies the value

     **Example:**
     ```swift
     var counter = EnhancedSynchronized(0)

     // Atomic increment
     counter.mutate { value in
         value += 1
     }

     // Dictionary operations
     var dict = EnhancedSynchronized([String: Int]())
     dict.mutate { d in
         d["key"] = (d["key"] ?? 0) + 1
     }

     // Conditional mutation
     var array = EnhancedSynchronized([1, 2, 3])
     array.mutate { arr in
         if arr.count < 10 {
             arr.append(4)
         }
     }
     ```
     */
    public func mutate(_ mutation: (inout Value) -> Void) {
        queue.sync(flags: .barrier) {
            mutation(&box.value)
        }
    }

    /**
     Perform an atomic mutation on the value and return a result.

     The closure receives an inout reference to the value, can modify it, and return a result.
     The entire operation is atomic - no other thread can read or write during the mutation.

     - Parameter mutation: Closure that modifies the value and returns a result
     - Returns: The result from the mutation closure

     **Example:**
     ```swift
     var counter = EnhancedSynchronized(0)

     // Atomic increment that returns new value
     let newValue = counter.mutate { value -> Int in
         value += 1
         return value
     }

     // Check-then-set pattern
     var dict = EnhancedSynchronized([String: String]())
     let created = dict.mutate { d -> Bool in
         if d["key"] != nil {
             return false  // Already exists
         }
         d["key"] = "value"
         return true  // Created
     }

     // Get-or-create pattern
     let item = dict.mutate { d -> String in
         if let existing = d["key"] {
             return existing
         }
         let new = "default"
         d["key"] = new
         return new
     }
     ```
     */
    public func mutate<Result>(_ mutation: (inout Value) -> Result) -> Result {
        queue.sync(flags: .barrier) {
            mutation(&box.value)
        }
    }
}
