@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class RingBufferTest: UnitTest {
    func test_EnqueueAndDequeue_ShouldHandleElementsInFIFOOrder() {
        var ringBuffer = RingBuffer<Int>(capacity: 3)
        ringBuffer.enqueue(1)
        ringBuffer.enqueue(2)

        XCTAssertEqual(ringBuffer.dequeue(), 1, "Dequeued element should be 1")
        XCTAssertEqual(ringBuffer.dequeue(), 2, "Dequeued element should be 2")
        XCTAssertNil(ringBuffer.dequeue(), "Buffer should be empty")
    }

    func test_EnqueueBeyondCapacity_ShouldRemoveOldestElement() {
        var ringBuffer = RingBuffer<Int>(capacity: 2)
        ringBuffer.enqueue(1)
        ringBuffer.enqueue(2)
        ringBuffer.enqueue(3) // This should remove the oldest element (1) to make room

        XCTAssertEqual(ringBuffer.dequeue(), 2, "Dequeued element should be 2 after overwriting")
        XCTAssertEqual(ringBuffer.dequeue(), 3, "Dequeued element should be 3")
        XCTAssertNil(ringBuffer.dequeue(), "Buffer should be empty")
    }

    func test_EnqueueCollection_ShouldHandleAllElements() {
        var ringBuffer = RingBuffer<Int>(capacity: 5)
        ringBuffer.enqueue(contentsOf: [1, 2, 3])

        XCTAssertEqual(ringBuffer.dequeue(), 1, "Dequeued element should be 1")
        XCTAssertEqual(ringBuffer.dequeue(), 2, "Dequeued element should be 2")
        XCTAssertEqual(ringBuffer.dequeue(), 3, "Dequeued element should be 3")
        XCTAssertNil(ringBuffer.dequeue(), "Buffer should be empty")
    }

    func test_EmptyAndFullStates_ShouldBeCorrect() {
        var ringBuffer = RingBuffer<Int>(capacity: 2)
        XCTAssertTrue(ringBuffer.isEmpty, "Buffer should initially be empty")

        ringBuffer.enqueue(1)
        ringBuffer.enqueue(2)
        XCTAssertFalse(ringBuffer.isEmpty, "Buffer should not be empty")
        XCTAssertTrue(ringBuffer.isBufferFull(), "Buffer should be full")

        _ = ringBuffer.dequeue()
        XCTAssertFalse(ringBuffer.isBufferFull(), "Buffer should not be full after dequeueing")
    }

    func test_toArray_ShouldReturnElementsInOrder() {
        var ringBuffer = RingBuffer<Int>(capacity: 3)
        ringBuffer.enqueue(1)
        ringBuffer.enqueue(2)
        let array = ringBuffer.toArray()

        XCTAssertEqual(array, [1, 2], "toArray should return elements in FIFO order")
    }
}
