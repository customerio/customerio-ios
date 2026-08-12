@testable import CioInternalCommonMocks
@_spi(Internal) @testable import CioMessagingPush
import SharedTests
import UserNotifications
import XCTest

final class NotificationDelegatePeerRegistryTests: XCTestCase {
    private final class Peer: NSObject, UNUserNotificationCenterDelegate {}

    private var registry: NotificationDelegatePeerRegistryImpl!

    override func setUp() {
        super.setUp()
        registry = NotificationDelegatePeerRegistryImpl()
    }

    override func tearDown() {
        registry = nil
        super.tearDown()
    }

    func testRegister_whenPeersAreDistinct_thenPreservesSequentialIdentityOrder() {
        let first = Peer()
        let second = Peer()

        registry.register(first)
        registry.register(second)

        let peers = registry.livePeers()
        XCTAssertEqual(peers.count, 2)
        XCTAssertTrue(peers[0] === first)
        XCTAssertTrue(peers[1] === second)
    }

    func testRegister_whenSamePeerIsAssignedTwice_thenStoresIdentityOnceInOriginalPosition() {
        let first = Peer()
        let second = Peer()

        registry.register(first)
        registry.register(second)
        registry.register(first)

        let peers = registry.livePeers()
        XCTAssertEqual(peers.count, 2)
        XCTAssertTrue(peers[0] === first)
        XCTAssertTrue(peers[1] === second)
    }

    func testRegister_whenNilIsFirstAssignment_thenRegistryRemainsEmpty() {
        registry.register(nil)

        XCTAssertTrue(registry.livePeers().isEmpty)
    }

    func testRegister_whenNilIsAssignedAfterPeers_thenClearsAllPeers() {
        let first = Peer()
        let second = Peer()
        registry.register(first)
        registry.register(second)

        registry.register(nil)

        XCTAssertTrue(registry.livePeers().isEmpty)
    }

    func testLivePeers_whenOwnerReleasesPeer_thenWeakReferenceIsCompacted() {
        var peer: Peer? = Peer()
        weak var weakPeer = peer
        registry.register(peer)

        peer = nil

        XCTAssertNil(weakPeer)
        XCTAssertTrue(registry.livePeers().isEmpty)
    }

    func testRegister_whenCapacityIsExceeded_thenEvictsOldestLivePeerDeterministically() {
        let peers = (0 ... NotificationDelegatePeerRegistryImpl.maxPeerCount).map { _ in Peer() }
        peers.forEach { registry.register($0) }

        let livePeers = registry.livePeers()
        XCTAssertEqual(livePeers.count, NotificationDelegatePeerRegistryImpl.maxPeerCount)
        XCTAssertFalse(livePeers.contains { $0 === peers[0] })

        for (index, livePeer) in livePeers.enumerated() {
            XCTAssertTrue(livePeer === peers[index + 1])
        }
    }

    func testRegister_whenDeadPeerExistsAtCapacity_thenCompactsBeforeEvictingLivePeer() {
        var peers = (0 ..< NotificationDelegatePeerRegistryImpl.maxPeerCount).map { _ in Peer() as Peer? }
        peers.forEach { registry.register($0) }
        weak var releasedPeer = peers[0]
        peers[0] = nil
        let newest = Peer()

        registry.register(newest)

        XCTAssertNil(releasedPeer)
        let livePeers = registry.livePeers()
        XCTAssertEqual(livePeers.count, NotificationDelegatePeerRegistryImpl.maxPeerCount)
        XCTAssertTrue(livePeers.last === newest)
        for peer in peers.dropFirst().compactMap({ $0 }) {
            XCTAssertTrue(livePeers.contains { $0 === peer })
        }
    }

    func testRegister_whenCalledConcurrently_thenRemainsBoundedAndContainsNoDuplicateIdentity() {
        let peers = (0 ..< 64).map { _ in Peer() }
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "io.customer.delegate-registry-stress", attributes: .concurrent)

        for iteration in 0 ..< 1000 {
            group.enter()
            queue.async { [registry, peers] in
                registry?.register(peers[iteration % peers.count])
                group.leave()
            }
        }

        XCTAssertEqual(group.wait(timeout: .now() + 5), .success)
        let livePeers = registry.livePeers()
        XCTAssertLessThanOrEqual(livePeers.count, NotificationDelegatePeerRegistryImpl.maxPeerCount)
        XCTAssertEqual(Set(livePeers.map(ObjectIdentifier.init)).count, livePeers.count)
    }
}
