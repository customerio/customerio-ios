import Foundation

/// A ring buffer (or circular buffer) is a fixed-size, array-based data structure
/// that is efficient for FIFO (First-In-First-Out) operations.
struct RingBuffer<T> {
    // The underlying array to store the elements. It has fixed capacity and may contain nil values.
    private var array: [T?]
    // Head and tail indices to keep track of the start and end of the queue.
    private var head: Int = 0, tail: Int = 0
    // The total capacity of the ring buffer.
    private var capacity: Int
    // Flag to indicate if the buffer is full.
    private var isFull: Bool = false

    // Public read-only accessor for isFull
    public func isBufferFull() -> Bool {
        isFull
    }

    /// Initializes the ring buffer with a specified capacity.
    /// - Parameter capacity: The maximum number of elements the buffer can hold.
    init(capacity: Int) {
        self.capacity = capacity
        self.array = Array(repeating: nil, count: capacity)
    }

    /// Adds an element to the end of the buffer.
    /// If the buffer is full, it removes the oldest element.
    /// - Parameter element: The element to be added.
    mutating func enqueue(_ element: T) {
        array[tail] = element
        tail = (tail + 1) % capacity
        if isFull {
            head = (head + 1) % capacity
        }
        isFull = head == tail
    }

    /// Removes and returns the oldest element from the buffer.
    /// Returns nil if the buffer is empty.
    /// - Returns: The dequeued element or nil.
    mutating func dequeue() -> T? {
        guard !isEmpty else { return nil }
        let element = array[head]
        array[head] = nil
        head = (head + 1) % capacity
        isFull = false
        return element
    }

    /// Adds a collection of elements to the buffer.
    /// - Parameter collection: An array of elements to add.
    mutating func enqueue(contentsOf collection: [T]) {
        for element in collection {
            enqueue(element)
        }
    }

    /// Checks if the buffer is empty.
    var isEmpty: Bool {
        !isFull && (head == tail)
    }

    /// Converts the buffer's elements to an array.
    /// The order of the elements in the array is the same as the order in the buffer.
    /// - Returns: An array of non-nil elements in the buffer.
    func toArray() -> [T] {
        var result = [T]()
        var index = head

        while index != tail {
            if let element = array[index] {
                result.append(element)
            }
            index = (index + 1) % capacity
        }

        return result
    }
}
