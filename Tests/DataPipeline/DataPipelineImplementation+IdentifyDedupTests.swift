@testable import CioAnalytics
@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
@testable import SharedTests
import XCTest

/// Tests for per-session identify dedup behavior added to
/// `DataPipelineImplementation.commonIdentifyProfile`.
///
/// Dedup contract (PR 1 of Phase 1 — Auto-Event Volume Optimization):
///   * Short-circuit only when the userId matches the last identified user
///     **and** both `attributesDict` and `attributesCodable` are nil.
///   * Empty dict (`[:]`) is NOT a short-circuit — it is an intentional
///     "no-op trait merge" the customer may rely on for backend behavior.
///   * Identify-with-traits passes through but updates the session tracker.
///   * `clearIdentify()` resets the tracker so the next identify (even for
///     the same userId) takes the full path including device-token
///     re-registration.
///   * The first identify per session always runs the full path so token
///     rotation and DCoU cadence are preserved on cold start.
class DataPipelineIdentifyDedupTests: IntegrationTest {
    private var outputReader: OutputReaderPlugin!

    private let deviceAttributesMock = DeviceAttributesProviderMock()
    private let globalDataStoreMock = GlobalDataStoreMock()
    private let dataPipelinesLoggerMock = DataPipelinesLoggerMock()

    override func setUpDependencies() {
        super.setUpDependencies()

        mockCollection.add(mocks: [deviceAttributesMock, globalDataStoreMock, dataPipelinesLoggerMock])

        diGraphShared.override(value: deviceAttributesMock, forType: DeviceAttributesProvider.self)
        diGraphShared.override(value: globalDataStoreMock, forType: GlobalDataStore.self)
        diGraphShared.override(value: dataPipelinesLoggerMock, forType: DataPipelinesLogger.self)
    }

    override func setUp() {
        super.setUp()

        outputReader = (customerIO.add(plugin: OutputReaderPlugin()) as? OutputReaderPlugin)
    }

    // MARK: - First identify per session always fires

    func test_identify_givenFirstIdentifyNoTraits_expectAnalyticsIdentifyCalled() {
        let givenIdentifier = String.random

        XCTAssertNil(analytics.userId)

        customerIO.identify(userId: givenIdentifier)

        XCTAssertEqual(analytics.userId, givenIdentifier)
        XCTAssertEqual(outputReader.identifyEvents.count, 1)
        XCTAssertEqual(outputReader.identifyEvents.last?.userId, givenIdentifier)
    }

    // MARK: - Dedup short-circuit

    func test_identify_givenSecondIdentifySameUserIdNoTraits_expectAnalyticsIdentifyNotCalled() {
        let givenIdentifier = String.random

        customerIO.identify(userId: givenIdentifier)
        XCTAssertEqual(outputReader.identifyEvents.count, 1)
        outputReader.resetPlugin()

        // Second identify with the same userId and no traits should be deduped.
        customerIO.identify(userId: givenIdentifier)

        XCTAssertEqual(outputReader.identifyEvents.count, 0)
        XCTAssertEqual(outputReader.events.count, 0)
        XCTAssertEqual(analytics.userId, givenIdentifier)
    }

    // MARK: - Empty dict is NOT deduped

    func test_identify_givenSecondIdentifySameUserIdEmptyDictTraits_expectAnalyticsIdentifyCalled() {
        let givenIdentifier = String.random

        customerIO.identify(userId: givenIdentifier)
        outputReader.resetPlugin()

        // Explicit empty-dict traits MUST pass through — customers may rely on
        // the empty-traits identify as a no-op trait merge.
        customerIO.identify(userId: givenIdentifier, traits: [String: Any]())

        XCTAssertEqual(outputReader.identifyEvents.count, 1)
        XCTAssertEqual(outputReader.identifyEvents.last?.userId, givenIdentifier)
    }

    // MARK: - With-traits passes through

    func test_identify_givenSecondIdentifySameUserIdWithTraits_expectAnalyticsIdentifyCalled() {
        let givenIdentifier = String.random
        let givenBody: [String: Any] = ["first_name": "Dana", "age": 30]
        let givenBodyTypeMap: [[String]: Any.Type] = [["age"]: Int.self]

        customerIO.identify(userId: givenIdentifier)
        outputReader.resetPlugin()

        customerIO.identify(userId: givenIdentifier, traits: givenBody)

        XCTAssertEqual(outputReader.identifyEvents.count, 1)
        guard let identifyEvent = outputReader.identifyEvents.last else {
            XCTFail("identify event must not be nil")
            return
        }
        XCTAssertEqual(identifyEvent.userId, givenIdentifier)
        XCTAssertMatches(identifyEvent.traits?.dictionaryValue, givenBody, withTypeMap: givenBodyTypeMap)
    }

    // MARK: - Profile change still fires

    func test_identify_givenDifferentUserIdNoTraits_expectAnalyticsIdentifyCalled() {
        let firstIdentifier = String.random
        let secondIdentifier = String.random
        XCTAssertNotEqual(firstIdentifier, secondIdentifier)

        customerIO.identify(userId: firstIdentifier)
        outputReader.resetPlugin()

        customerIO.identify(userId: secondIdentifier)

        XCTAssertEqual(outputReader.identifyEvents.count, 1)
        XCTAssertEqual(outputReader.identifyEvents.last?.userId, secondIdentifier)
        XCTAssertEqual(analytics.userId, secondIdentifier)
    }

    // MARK: - clearIdentify resets the session flag

    func test_identify_givenSameUserIdAfterClearIdentify_expectAnalyticsIdentifyCalled() {
        let givenIdentifier = String.random

        customerIO.identify(userId: givenIdentifier)
        customerIO.clearIdentify()
        outputReader.resetPlugin()

        // After clearIdentify, the same userId must be re-emitted (session flag reset).
        customerIO.identify(userId: givenIdentifier)

        XCTAssertEqual(outputReader.identifyEvents.count, 1)
        XCTAssertEqual(outputReader.identifyEvents.last?.userId, givenIdentifier)
    }

    // MARK: - Regression guard: device-token re-registration runs on first identify

    func test_identify_givenFirstIdentify_expectDeviceTokenReregistrationCalled() {
        let givenIdentifier = String.random
        let givenDeviceToken = String.random

        globalDataStoreMock.underlyingPushDeviceToken = givenDeviceToken
        mockDeviceAttributes()

        customerIO.identify(userId: givenIdentifier)

        // First identify with a registered device token must fire a
        // "Device Created or Updated" event for the new profile.
        let updatedEvents = outputReader.deviceUpdateEvents
        XCTAssertEqual(updatedEvents.count, 1)
        XCTAssertEqual(updatedEvents.first?.deviceToken, givenDeviceToken)
    }

    // MARK: - Helpers

    private func mockDeviceAttributes(defaultAttributes: [String: Any] = [:]) {
        deviceAttributesMock.getDefaultDeviceAttributesClosure = { $0(defaultAttributes) }
    }
}
