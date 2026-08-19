@_spi(Internal) @testable import CioMessagingPush
import XCTest

final class PeerDeliveryCompletionAggregateTests: XCTestCase {
    private final class LifetimeToken {}

    private final class DeinitCallbackToken {
        private let callback: () -> Void

        init(callback: @escaping () -> Void) {
            self.callback = callback
        }

        deinit {
            callback()
        }
    }

    func testAggregate_whenPeersCompleteSynchronouslyBeforeDispatchFinishes_thenOuterCompletesOnceAfterDispatch() {
        var values: [Int] = []
        let aggregate = PeerDeliveryCompletionAggregate<[Int]>(
            retaining: [LifetimeToken(), LifetimeToken()],
            initialValue: [],
            merge: { $0 + $1 },
            onFinished: { values = $0 }
        )

        aggregate.complete(token: 0, with: [1])
        aggregate.complete(token: 1, with: [2])
        XCTAssertTrue(values.isEmpty)

        aggregate.finishDispatching()
        XCTAssertEqual(values, [1, 2])
    }

    func testAggregate_whenPeersCompleteOutOfOrderAndDuplicate_thenEachTokenContributesOnce() {
        let completion = expectation(description: "outer completion")
        completion.assertForOverFulfill = true
        var result: Set<Int> = []
        let aggregate = PeerDeliveryCompletionAggregate<Set<Int>>(
            retaining: [LifetimeToken(), LifetimeToken(), LifetimeToken()],
            initialValue: [],
            merge: { $0.union($1) },
            onFinished: {
                result = $0
                completion.fulfill()
            }
        )
        aggregate.finishDispatching()

        aggregate.complete(token: 2, with: [3])
        aggregate.complete(token: 2, with: [99])
        aggregate.complete(token: 0, with: [1])
        XCTAssertTrue(result.isEmpty)
        aggregate.complete(token: 1, with: [2])
        aggregate.complete(token: 0, with: [98])

        wait(for: [completion], timeout: 1)
        XCTAssertEqual(result, [1, 2, 3])
    }

    func testAggregate_whenNoPeersExist_thenFinishDispatchingCompletesWithInitialValue() {
        var result: Int?
        let aggregate = PeerDeliveryCompletionAggregate<Int>(
            retaining: [],
            initialValue: 42,
            merge: +,
            onFinished: { result = $0 }
        )

        aggregate.finishDispatching()
        aggregate.finishDispatching()

        XCTAssertEqual(result, 42)
    }

    func testAggregate_whenOneClaimedPeerNeverCompletes_thenOuterRemainsPendingUntilThatPeerCompletes() {
        let prematureCompletion = expectation(description: "outer does not complete early")
        prematureCompletion.isInverted = true
        let eventualCompletion = expectation(description: "outer completes after final peer")
        var isWaitingForFinalPeer = true
        var completionCount = 0
        let aggregate = PeerDeliveryCompletionAggregate<Void>(
            retaining: [LifetimeToken(), LifetimeToken()],
            initialValue: (),
            merge: { _, _ in () },
            onFinished: {
                completionCount += 1
                if isWaitingForFinalPeer {
                    prematureCompletion.fulfill()
                } else {
                    eventualCompletion.fulfill()
                }
            }
        )

        aggregate.finishDispatching()
        aggregate.complete(token: 0, with: ())
        wait(for: [prematureCompletion], timeout: 0.05)

        isWaitingForFinalPeer = false
        aggregate.complete(token: 1, with: ())
        aggregate.complete(token: 1, with: ())
        wait(for: [eventualCompletion], timeout: 1)
        XCTAssertEqual(completionCount, 1)
    }

    func testAggregate_whenPeerDiscardsCompletion_thenAbandonmentCleanupRuns() {
        var abandonmentCount = 0

        do {
            let aggregate = PeerDeliveryCompletionAggregate<Void>(
                retaining: [LifetimeToken()],
                initialValue: (),
                merge: { _, _ in () },
                onFinished: { _ in XCTFail("incomplete delivery must not finish") },
                onAbandoned: { abandonmentCount += 1 }
            )
            aggregate.finishDispatching()
        }

        XCTAssertEqual(abandonmentCount, 1)
    }

    func testAggregate_whenDeliveryCompletes_thenAbandonmentCleanupDoesNotRun() {
        var abandonmentCount = 0

        do {
            let aggregate = PeerDeliveryCompletionAggregate<Void>(
                retaining: [LifetimeToken()],
                initialValue: (),
                merge: { _, _ in () },
                onFinished: { _ in },
                onAbandoned: { abandonmentCount += 1 }
            )

            aggregate.finishDispatching()
            aggregate.complete(token: 0, with: ())
        }

        XCTAssertEqual(abandonmentCount, 0)
    }

    func testAggregate_whenOuterHandlerReenters_thenSnapshotIsRetainedUntilOuterReturns() {
        var token: LifetimeToken? = LifetimeToken()
        weak var weakToken = token
        var aggregate: PeerDeliveryCompletionAggregate<Void>!
        aggregate = PeerDeliveryCompletionAggregate<Void>(
            retaining: [token!],
            initialValue: (),
            merge: { _, _ in () },
            onFinished: {
                XCTAssertNotNil(weakToken)
                aggregate.complete(token: 0, with: ())
                aggregate.finishDispatching()
                XCTAssertNotNil(weakToken)
            }
        )
        token = nil

        aggregate.finishDispatching()
        aggregate.complete(token: 0, with: ())

        XCTAssertNil(weakToken)
    }

    func testAggregate_whenReleasedPeerDeinitReenters_thenReleaseRunsOutsideAggregateLock() {
        let deinitialized = expectation(description: "peer deinitialized without deadlock")
        var aggregate: PeerDeliveryCompletionAggregate<Void>!
        var token: DeinitCallbackToken? = DeinitCallbackToken {
            aggregate.finishDispatching()
            deinitialized.fulfill()
        }
        aggregate = PeerDeliveryCompletionAggregate<Void>(
            retaining: [token!],
            initialValue: (),
            merge: { _, _ in () },
            onFinished: { _ in }
        )
        token = nil

        aggregate.finishDispatching()
        aggregate.complete(token: 0, with: ())

        wait(for: [deinitialized], timeout: 1)
    }

    func testAggregate_whenConcurrentCompletionsRace_thenOuterCompletesExactlyOnce() {
        let peerCount = 64
        let completion = expectation(description: "outer completion")
        completion.assertForOverFulfill = true
        let lock = NSLock()
        var completionCount = 0
        let aggregate = PeerDeliveryCompletionAggregate<Set<Int>>(
            retaining: (0 ..< peerCount).map { _ in LifetimeToken() },
            initialValue: [],
            merge: { $0.union($1) },
            onFinished: { result in
                lock.lock()
                completionCount += 1
                lock.unlock()
                XCTAssertEqual(result, Set(0 ..< peerCount))
                completion.fulfill()
            }
        )
        aggregate.finishDispatching()

        DispatchQueue.concurrentPerform(iterations: peerCount * 4) { iteration in
            let token = iteration % peerCount
            aggregate.complete(token: token, with: [token])
        }

        wait(for: [completion], timeout: 5)
        lock.lock()
        let finalCount = completionCount
        lock.unlock()
        XCTAssertEqual(finalCount, 1)
    }
}
