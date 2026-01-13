import Foundation

/// A ring buffer (or circular buffer) is a fixed-size, array-based data structure
/// that is efficient for FIFO (First-In-First-Out) operations.
struct RingBuffer<Element> {
    /// The internal storage for the buffer. Once created, the storage size should never expand.
    private var array: [Element?]

    /// The total capacity of the ring buffer.
    let capacity: Int

    /// The index where the first value will be read from
    private(set) var headIndex: Int = 0

    /// The index where appended values will be written to
    private(set) var tailIndex: Int = 0

    /// The number of element stored in the RingBuffer. This will always be less than or equal to capacity
    private(set) var count = 0

    /// Flag to indicate if the buffer is full.
    var isFull: Bool {
        count == capacity
    }

    /// Checks if the buffer is empty.
    var isEmpty: Bool {
        count == 0
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
    mutating func enqueue(_ element: Element) {
        array[tailIndex] = element
        if isFull {
            headIndex = (headIndex + 1) % capacity
        } else {
            count += 1
        }
        tailIndex = (tailIndex + 1) % capacity
    }

    /// Removes and returns the oldest element from the buffer.
    /// Returns nil if the buffer is empty.
    /// - Returns: The dequeued element or nil.
    mutating func dequeue() -> Element? {
        guard !isEmpty else { return nil }
        let element = array[headIndex]
        array[headIndex] = nil
        headIndex = (headIndex + 1) % capacity
        count -= 1
        return element
    }

    /// Adds a sequence of elements to the buffer.
    /// - Parameter collection: A collection of items to insert, generally an Array or ArraySlice.
    mutating func enqueue<C>(contentsOf collection: C) where C: Collection, C.Element == Element {
        guard !collection.isEmpty else { return }

        // We can never insert more than our capacity, so just trim it to begin
        let trimmedInsert = collection.suffix(capacity)

        // In the worst case, we need to do two replace operations: Tail..<Capacity and 0..<Tail.
        // In some cases, the first part is enough. When it isn't, recursion prevents code duplication.
        let firstPart = trimmedInsert.prefix(capacity - tailIndex)
        let secondPart = trimmedInsert.dropFirst(capacity - tailIndex)

        // This may clobber the position of head. We correct for that below
        array.replaceSubrange(tailIndex ..< (tailIndex + firstPart.count), with: Array(firstPart))
        tailIndex = (tailIndex + firstPart.count) % capacity
        count += firstPart.count

        // This catches if we clobbered the head position. If we did, we advance head
        // to the next element to read.
        if count >= capacity {
            headIndex = (headIndex + count) % capacity
            count = capacity
        }

        // Use recursion for the second half
        if !secondPart.isEmpty {
            enqueue(contentsOf: secondPart)
        }
    }

    /// Converts the buffer's elements to an array.
    /// The order of the elements in the array is the same as the order in the buffer.
    /// - Returns: An array of non-nil elements in the buffer, in FIFO order
    func toArray() -> [Element] {
        if isEmpty {
            return []
        } else if tailIndex > headIndex {
            return Array(array[headIndex ..< tailIndex].compactMap(\.self))
        } else {
            return Array(array[headIndex ..< capacity].compactMap(\.self) + array[0 ..< tailIndex].compactMap(\.self))
        }
    }
}
