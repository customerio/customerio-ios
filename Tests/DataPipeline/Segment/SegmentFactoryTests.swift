@testable import CioAnalytics
@testable import CioDataPipelines
@testable import CioInternalCommon
import SharedTests
import XCTest

class SegmentFactoryTests: UnitTest {
    // With nothing overridden, the SDK builds Segment exactly as it did before the gateway: from the
    // configuration it generates, handed to `Analytics(configuration:)` as it is.
    func test_segmentFactory_givenNoOverride_expectSegmentBuiltFromGivenConfiguration() {
        let givenConfiguration = Configuration(writeKey: String.random)

        let analytics = diGraphShared.segmentFactory.makeAnalytics(givenConfiguration)
        defer {
            analytics.storage.hardReset(doYouKnowHowToUseThis: true)
            Analytics.removeActiveWriteKey(givenConfiguration.values.writeKey)
        }

        XCTAssertTrue(analytics.configuration === givenConfiguration)
    }

    func test_segmentFactory_givenNoOverride_expectGatewayPassesToGivenAnalytics() {
        let givenAnalytics = analytics!

        let gateway = diGraphShared.segmentFactory.makeGateway(givenAnalytics)

        let loggingGateway = gateway as? LoggingSegmentGateway
        let liveGateway = loggingGateway?.gateway as? AnalyticsSegmentGateway
        XCTAssertNotNil(liveGateway)
        XCTAssertTrue(liveGateway?.analytics === givenAnalytics)
    }

    // The base class builds the implementation with no override: its Segment is configured as the SDK
    // configures it, and every hand-off goes to that same instance.
    func test_dataPipelineImplementation_givenNoOverride_expectAnalyticsConfiguredAsBefore() {
        let implementation = DataPipeline.shared.implementation as? DataPipelineImplementation
        let expected = dataPipelineConfigOptions.toSegmentConfiguration().values
        let actual = implementation?.analytics.configuration.values

        XCTAssertEqual(actual?.writeKey, expected.writeKey)
        XCTAssertEqual(actual?.apiHost, expected.apiHost)
        XCTAssertEqual(actual?.cdnHost, expected.cdnHost)
        XCTAssertEqual(actual?.autoAddSegmentDestination, expected.autoAddSegmentDestination)
        XCTAssertEqual(actual?.trackApplicationLifecycleEvents, expected.trackApplicationLifecycleEvents)
        XCTAssertEqual(actual?.flushAt, expected.flushAt)
        XCTAssertEqual(actual?.flushInterval, expected.flushInterval)
        XCTAssertEqual(actual?.operatingMode, expected.operatingMode)
        XCTAssertEqual(actual?.flushPolicies.map { String(describing: type(of: $0)) }, expected.flushPolicies.map { String(describing: type(of: $0)) })
        let liveGateway = (implementation?.segment as? LoggingSegmentGateway)?.gateway as? AnalyticsSegmentGateway
        XCTAssertTrue(liveGateway?.analytics === implementation?.analytics)
    }
}
