@testable import CioInternalCommon
@testable import CioInternalCommonMocks
import Foundation
import SharedTests
import XCTest

/// The app group container does not exist in a unit test host, so the concrete store resolves no
/// file and returns early from everything. This stands one in for it.
private final class StubAppGroupFileManager: FileManager {
    let container: URL

    init(container: URL) {
        self.container = container
        super.init()
    }

    override func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? {
        container
    }
}

/// Resilience of the app-group pending queue: one undecodable row must not discard the rest, and
/// a file that cannot be read must never be written over — the NSE runs on pushes that arrive
/// before the first unlock after a reboot, when the app group file is still protected.
final class CioAppGroupPendingPushDeliveryStoreTests: UnitTest {
    private var container: URL!
    private var logger: LoggerMock!

    private var metricsFile: URL {
        container
            .appendingPathComponent(PendingPushDeliveryMetricsConstants.storageSubdirectoryName, isDirectory: true)
            .appendingPathComponent(PendingPushDeliveryMetricsConstants.storageFileName, isDirectory: false)
    }

    override func setUp() {
        super.setUp()
        container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        logger = LoggerMock()
    }

    override func tearDown() {
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: metricsFile.path)
        try? FileManager.default.removeItem(at: container)
        super.tearDown()
    }

    private func makeStore() -> CioAppGroupPendingPushDeliveryStore {
        CioAppGroupPendingPushDeliveryStore(
            appGroupId: "group.test.app.cio",
            processBundleIdentifier: "com.example.app",
            logger: logger,
            fileManager: StubAppGroupFileManager(container: container)
        )
    }

    private func makeMetric(deliveryId: String = "d1") -> PendingPushDeliveryMetric {
        PendingPushDeliveryMetric(
            deliveryId: deliveryId,
            deviceToken: "token",
            event: .delivered,
            timestamp: Date(timeIntervalSince1970: 1700000000)
        )
    }

    private func plant(_ json: String) throws {
        try FileManager.default.createDirectory(
            at: metricsFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(json.utf8).write(to: metricsFile)
    }

    private func logged(_ needle: String) -> Bool {
        logger.errorReceivedInvocations.contains { $0.message.contains(needle) }
    }

    /// The second row has no `device_id`. Every field on the metric is non-optional, so schema
    /// evolution alone reaches this — and one of them used to discard the other rows with it.
    private static let oneGoodOneBadRow = """
    [
      {"id":"6C7E1B2A-0000-4000-8000-000000000001","delivery_id":"d1","device_id":"token","event":"delivered","timestamp":"2023-11-14T22:13:20.000Z"},
      {"id":"6C7E1B2A-0000-4000-8000-000000000002","delivery_id":"d2","event":"delivered","timestamp":"2023-11-14T22:13:21.000Z"}
    ]
    """

    func test_read_givenOneUndecodableRow_expectTheOtherRowSurvives() throws {
        try plant(Self.oneGoodOneBadRow)

        guard case .rows(let rows) = makeStore().read() else {
            return XCTFail("expected rows, got unreadable")
        }

        XCTAssertEqual(rows.map(\.deliveryId), ["d1"])
        XCTAssertTrue(logged("skipped 1 of 2 row(s)"))
    }

    func test_append_givenOneUndecodableRow_expectTheGoodRowKept() throws {
        try plant(Self.oneGoodOneBadRow)
        let store = makeStore()

        XCTAssertTrue(store.append(makeMetric(deliveryId: "d3")))

        XCTAssertEqual(store.loadAll().map(\.deliveryId), ["d1", "d3"])
    }

    /// The defect. Modelled with a file the process may not read but whose directory it may still
    /// write, which is the shape Data Protection produces: an atomic write would otherwise succeed
    /// and replace rows that were never lost.
    func test_append_givenAnUnreadableFile_expectRefusedAndTheQueueUntouched() throws {
        let store = makeStore()
        XCTAssertTrue(store.append(makeMetric()))
        let before = try Data(contentsOf: metricsFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: metricsFile.path)

        XCTAssertFalse(store.append(makeMetric(deliveryId: "d2")))

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: metricsFile.path)
        XCTAssertEqual(try Data(contentsOf: metricsFile), before)
    }

    func test_read_givenAnUnreadableFile_expectUnreadableNotEmpty() throws {
        let store = makeStore()
        XCTAssertTrue(store.append(makeMetric()))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: metricsFile.path)

        XCTAssertEqual(store.read(), .unreadable)
        XCTAssertTrue(logged("could not be read, leaving it intact"))
    }

    /// `remove(id:)` is the NSE success path, so it is the one that runs on every delivered push.
    func test_remove_givenAnUnreadableFile_expectRefusedAndTheQueueUntouched() throws {
        let store = makeStore()
        let metric = makeMetric()
        XCTAssertTrue(store.append(metric))
        let before = try Data(contentsOf: metricsFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: metricsFile.path)

        XCTAssertFalse(store.remove(id: metric.id))

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: metricsFile.path)
        XCTAssertEqual(try Data(contentsOf: metricsFile), before)
    }

    func test_removeAll_givenAnUnreadableFile_expectRefusedAndTheQueueUntouched() throws {
        let store = makeStore()
        let metric = makeMetric()
        XCTAssertTrue(store.append(metric))
        let before = try Data(contentsOf: metricsFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: metricsFile.path)

        XCTAssertFalse(store.removeAll(ids: [metric.id]))

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: metricsFile.path)
        XCTAssertEqual(try Data(contentsOf: metricsFile), before)
    }

    /// Read succeeded and the bytes are not a row array, so unlike a read failure there is nothing
    /// left to preserve — the next write reclaims the file.
    func test_append_givenAFileThatIsNotARowArray_expectTheWriteProceeds() throws {
        try plant("{\"not\":\"an array\"}")
        let store = makeStore()

        XCTAssertTrue(store.append(makeMetric()))

        XCTAssertEqual(store.loadAll().map(\.deliveryId), ["d1"])
        XCTAssertTrue(logged("not a row array"))
    }

    func test_read_givenNoFile_expectEmptyNotUnreadable() {
        XCTAssertEqual(makeStore().read(), .rows([]))
    }
}
