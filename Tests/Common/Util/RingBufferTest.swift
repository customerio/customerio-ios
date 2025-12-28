@testable import CioInternalCommon
import Foundation
import SharedTests
import Testing

struct RingBufferTest {
    @Test
    func test_EnqueueAndDequeue_ShouldHandleElementsInFIFOOrder() throws {
        var ringBuffer = RingBuffer<Int>(capacity: 3)
        ringBuffer.enqueue(1)
        ringBuffer.enqueue(2)

        #expect(ringBuffer.dequeue() == 1, "Dequeued element should be 1")
        #expect(ringBuffer.dequeue() == 2, "Dequeued element should be 2")
        #expect(ringBuffer.dequeue() == nil, "Buffer should be empty")
    }

    @Test
    func test_EnqueueBeyondCapacity_ShouldRemoveOldestElement() throws {
        var ringBuffer = RingBuffer<Int>(capacity: 2)
        ringBuffer.enqueue(1)
        ringBuffer.enqueue(2)
        ringBuffer.enqueue(3) // This should remove the oldest element (1) to make room

        #expect(ringBuffer.dequeue() == 2, "Dequeued element should be 2 after overwriting")
        #expect(ringBuffer.dequeue() == 3, "Dequeued element should be 3")
        #expect(ringBuffer.dequeue() == nil, "Buffer should be empty")
    }

    @Test
    func test_EnqueueCollection_ShouldHandleAllElements() throws {
        var ringBuffer = RingBuffer<Int>(capacity: 5)
        ringBuffer.enqueue(contentsOf: [1, 2, 3])

        #expect(ringBuffer.dequeue() == 1, "Dequeued element should be 1")
        #expect(ringBuffer.dequeue() == 2, "Dequeued element should be 2")
        #expect(ringBuffer.dequeue() == 3, "Dequeued element should be 3")
        #expect(ringBuffer.dequeue() == nil, "Buffer should be empty")
    }
    
    @Test
    func test_appendArraySmallerThanEnd() throws {
        var ringBuffer = RingBuffer<String>(capacity: 6)
        // Advance head and tail
        ringBuffer.enqueue("a")
        ringBuffer.enqueue("b")
        ringBuffer.enqueue("c")

        _ = ringBuffer.dequeue()
        _ = ringBuffer.dequeue()
        #expect(ringBuffer.count == 1)
        #expect(ringBuffer.headIndex == 2)
        #expect(ringBuffer.tailIndex == 3)

        ringBuffer.enqueue(contentsOf: ["d", "e"])
        #expect(ringBuffer.count == 3)
        #expect(ringBuffer.headIndex == 2)
        #expect(ringBuffer.tailIndex == 5)

        #expect(ringBuffer.toArray() == ["c", "d", "e"])
        #expect(ringBuffer.dequeue() == "c")
        #expect(ringBuffer.dequeue() == "d")
        #expect(ringBuffer.dequeue() == "e")
        
        #expect(ringBuffer.count == 0)
        #expect(ringBuffer.headIndex == 5)
        #expect(ringBuffer.tailIndex == 5)
    }

    @Test
    func test_appendArrayFillingToEnd() throws {
        var ringBuffer = RingBuffer<String>(capacity: 5)
        // Advance head and tail
        ringBuffer.enqueue("a")
        ringBuffer.enqueue("b")
        ringBuffer.enqueue("c")

        _ = ringBuffer.dequeue()
        _ = ringBuffer.dequeue()
        #expect(ringBuffer.count == 1)
        #expect(ringBuffer.headIndex == 2)
        #expect(ringBuffer.tailIndex == 3)

        ringBuffer.enqueue(contentsOf: ["d", "e"])
        #expect(ringBuffer.count == 3)
        #expect(ringBuffer.headIndex == 2)
        #expect(ringBuffer.tailIndex == 0)

        #expect(ringBuffer.toArray() == ["c", "d", "e"])
        #expect(ringBuffer.dequeue() == "c")
        #expect(ringBuffer.dequeue() == "d")
        #expect(ringBuffer.dequeue() == "e")
        #expect(ringBuffer.count == 0)
        #expect(ringBuffer.headIndex == 0)
        #expect(ringBuffer.tailIndex == 0)
    }

    @Test
    func test_appendArrayFillingBeyondEnd() throws {
        var ringBuffer = RingBuffer<String>(capacity: 4)
        // Advance head and tail
        ringBuffer.enqueue("a")
        ringBuffer.enqueue("b")
        ringBuffer.enqueue("c")

        _ = ringBuffer.dequeue()
        _ = ringBuffer.dequeue()
        #expect(ringBuffer.count == 1)
        #expect(ringBuffer.headIndex == 2)
        #expect(ringBuffer.tailIndex == 3)

        ringBuffer.enqueue(contentsOf: ["d", "e"])
        #expect(ringBuffer.count == 3)
        #expect(ringBuffer.headIndex == 2)
        #expect(ringBuffer.tailIndex == 1)

        #expect(ringBuffer.toArray() == ["c", "d", "e"])
        #expect(ringBuffer.dequeue() == "c")
        #expect(ringBuffer.dequeue() == "d")
        #expect(ringBuffer.dequeue() == "e")
        #expect(ringBuffer.count == 0)
        #expect(ringBuffer.headIndex == 1)
        #expect(ringBuffer.tailIndex == 1)
    }

    @Test
    func test_appendArrayFillingToExactCapacity() throws {
        var ringBuffer = RingBuffer<String>(capacity: 3)
        // Advance head and tail
        ringBuffer.enqueue("a")
        ringBuffer.enqueue("b")
        ringBuffer.enqueue("c")

        _ = ringBuffer.dequeue()
        _ = ringBuffer.dequeue()
        #expect(ringBuffer.count == 1)
        #expect(ringBuffer.headIndex == 2)
        #expect(ringBuffer.tailIndex == 0)

        ringBuffer.enqueue(contentsOf: ["d", "e"])
        #expect(ringBuffer.count == 3)
        #expect(ringBuffer.headIndex == 2)
        #expect(ringBuffer.tailIndex == 2)

        #expect(ringBuffer.toArray() == ["c", "d", "e"])
        #expect(ringBuffer.dequeue() == "c")
        #expect(ringBuffer.dequeue() == "d")
        #expect(ringBuffer.dequeue() == "e")
        #expect(ringBuffer.count == 0)
        #expect(ringBuffer.headIndex == 2)
        #expect(ringBuffer.tailIndex == 2)
    }

    @Test
    func test_appendArrayInsertingExactCapacity() throws {
        var ringBuffer = RingBuffer<String>(capacity: 5)
        // Advance tail
        ringBuffer.enqueue("a")
        ringBuffer.enqueue("b")
        ringBuffer.enqueue("c")

        #expect(ringBuffer.count == 3)
        #expect(ringBuffer.headIndex == 0)
        #expect(ringBuffer.tailIndex == 3)

        ringBuffer.enqueue(contentsOf: ["d", "e", "f", "g", "h"])
        #expect(ringBuffer.count == 5)
        #expect(ringBuffer.headIndex == 3)
        #expect(ringBuffer.tailIndex == 3)

        #expect(ringBuffer.toArray() == ["d", "e", "f", "g", "h"])
        #expect(ringBuffer.dequeue() == "d")
        #expect(ringBuffer.dequeue() == "e")
        #expect(ringBuffer.dequeue() == "f")
        #expect(ringBuffer.dequeue() == "g")
        #expect(ringBuffer.dequeue() == "h")
        #expect(ringBuffer.count == 0)
        #expect(ringBuffer.headIndex == 3)
        #expect(ringBuffer.tailIndex == 3)
    }

    @Test
    func test_appendArrayInsertingGreaterThanCapacity() throws {
        var ringBuffer = RingBuffer<String>(capacity: 5)
        // Advance tail
        ringBuffer.enqueue("a")
        ringBuffer.enqueue("b")
        ringBuffer.enqueue("c")

        #expect(ringBuffer.count == 3)
        #expect(ringBuffer.headIndex == 0)
        #expect(ringBuffer.tailIndex == 3)

        ringBuffer.enqueue(contentsOf: ["d", "e", "f", "g", "h", "i", "j", "k"])
        #expect(ringBuffer.count == 5)
        #expect(ringBuffer.headIndex == 3)
        #expect(ringBuffer.tailIndex == 3)

        #expect(ringBuffer.toArray() == ["g", "h", "i", "j", "k"])
        #expect(ringBuffer.dequeue() == "g")
        #expect(ringBuffer.dequeue() == "h")
        #expect(ringBuffer.dequeue() == "i")
        #expect(ringBuffer.dequeue() == "j")
        #expect(ringBuffer.dequeue() == "k")
        #expect(ringBuffer.count == 0)
        #expect(ringBuffer.headIndex == 3)
        #expect(ringBuffer.tailIndex == 3)
    }

    
    @Test
    func test_EmptyAndFullStates_ShouldBeCorrect() throws {
        var ringBuffer = RingBuffer<Int>(capacity: 2)
        #expect(ringBuffer.isEmpty, "Buffer should initially be empty")

        ringBuffer.enqueue(1)
        ringBuffer.enqueue(2)
        #expect(!ringBuffer.isEmpty, "Buffer should not be empty")
        #expect(ringBuffer.isFull, "Buffer should be full")

        _ = ringBuffer.dequeue()
        #expect(!ringBuffer.isFull, "Buffer should not be full after dequeueing")
    }

    @Test
    func test_toArray_ShouldReturnElementsInOrder() throws {
        var ringBuffer = RingBuffer<Int>(capacity: 3)
        ringBuffer.enqueue(1)
        ringBuffer.enqueue(2)
        let array = ringBuffer.toArray()

        #expect(array == [1, 2], "toArray should return elements in FIFO order")
    }
}
