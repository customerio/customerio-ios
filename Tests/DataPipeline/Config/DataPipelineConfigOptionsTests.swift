@testable import CioAnalytics
@testable import CioDataPipelines
import SharedTests
import XCTest

// Tests to verify that configurations created by the SDK for our DataPipeline module and Segment analytics matches our expectations.
class DataPipelineConfigOptionsTests: UnitTest {
    // Verifies that our default values match Segment's default values.
    // If the test fails, it means Segment has changed their default values and we know that there
    // is a mismatch between our default values and Segment's default values.
    func test_doNotModifyDataPipelineConfig_expectMatchWithAnalyticsDefaults() {
        let givenCdpApiKey = String.random
        let (_, dataPipelineConfig) = SDKConfigBuilder(cdpApiKey: givenCdpApiKey).build()
        let analyticsConfig = Configuration(writeKey: givenCdpApiKey).values

        // apiHost, cdnHost, defaultSettings and autoAddSegmentDestination will always be different
        // because they are overridden while creating the analytics configuration.
        // Function below this test should verify that these values are overridden.
        // Remaining values should match here.
        XCTAssertEqual(dataPipelineConfig.cdpApiKey, analyticsConfig.writeKey)
        XCTAssertEqual(dataPipelineConfig.trackApplicationLifecycleEvents, analyticsConfig.trackApplicationLifecycleEvents)
        XCTAssertEqual(dataPipelineConfig.flushAt, analyticsConfig.flushAt)
        XCTAssertEqual(dataPipelineConfig.flushInterval, analyticsConfig.flushInterval)
        XCTAssertSame(dataPipelineConfig.flushPolicies, analyticsConfig.flushPolicies)
    }

    // Verifies that the configuration generated by the SDK without any modifications for analytics
    // matches our expectations.
    // If the test fails, it means that either our default values our analytics default configuration
    // that we expect have been changed.
    // One major difference between above test and this test is that it verifies using configuration
    // generated by our SDK for analytics. While above test verifies using the configuration generated
    // directly by Segment Configuration class.
    func test_doNotModifyDataPipelineConfig_expectAnalyticsConfigMatchExpectations() {
        let givenCdpApiKey = String.random
        let (_, dataPipelineConfig) = SDKConfigBuilder(cdpApiKey: givenCdpApiKey).build()
        let analyticsConfig = dataPipelineConfig.toSegmentConfiguration().values

        // These values are overridden while creating the analytics configuration and should match
        // Customer.io's DataPipeline settings.
        XCTAssertEqual(analyticsConfig.apiHost, "cdp.customer.io/v1")
        XCTAssertEqual(analyticsConfig.cdnHost, "cdp.customer.io/v1")
        XCTAssertNil(analyticsConfig.defaultSettings)
        XCTAssertFalse(analyticsConfig.autoAddSegmentDestination)
        // These values should match provided values.
        XCTAssertEqual(analyticsConfig.writeKey, givenCdpApiKey)
        // These values should match Segment's default values.
        XCTAssertEqual(analyticsConfig.trackApplicationLifecycleEvents, true)
        XCTAssertEqual(analyticsConfig.flushAt, 20)
        XCTAssertEqual(analyticsConfig.flushInterval, 30.0)
        XCTAssertSame(analyticsConfig.flushPolicies, [CountBasedFlushPolicy(), IntervalBasedFlushPolicy()])
        XCTAssertEqual(analyticsConfig.operatingMode, OperatingMode.asynchronous)
        XCTAssertSame(analyticsConfig.flushQueue, DispatchQueue(label: "com.segment.operatingModeQueue", qos: .utility))
    }

    // Verifies that analytics configuration generated by our SDK matches the values provided by the user.
    func test_modifyDataPipelineConfig_expectAnalyticsConfigMatchExpectations() {
        let givenCdpApiKey = String.random
        let givenApiHost = String.random
        let givenCdnHost = String.random
        let givenFlushAt = 17
        let givenFlushInterval = 23.7
        let givenFlushPolicies: [FlushPolicy] = [CountBasedFlushPolicy()]
        let givenTrackApplicationLifecycleEvents = false

        let (_, dataPipelineConfig) = SDKConfigBuilder(cdpApiKey: givenCdpApiKey)
            .apiHost(givenApiHost)
            .cdnHost(givenCdnHost)
            .flushAt(givenFlushAt)
            .flushInterval(givenFlushInterval)
            .flushPolicies(givenFlushPolicies)
            .trackApplicationLifecycleEvents(givenTrackApplicationLifecycleEvents)
            .build()
        let analyticsConfig = dataPipelineConfig.toSegmentConfiguration().values

        XCTAssertEqual(analyticsConfig.writeKey, givenCdpApiKey)
        XCTAssertEqual(analyticsConfig.trackApplicationLifecycleEvents, givenTrackApplicationLifecycleEvents)
        XCTAssertEqual(analyticsConfig.flushAt, givenFlushAt)
        XCTAssertEqual(analyticsConfig.flushInterval, givenFlushInterval)
        XCTAssertEqual(analyticsConfig.apiHost, givenApiHost)
        XCTAssertEqual(analyticsConfig.cdnHost, givenCdnHost)
        XCTAssertSame(analyticsConfig.flushPolicies, givenFlushPolicies)
    }
}

// Helper methods to assert custom types.
// Added extension to UnitTest so that these methods can be used by SDKConfigBuilderTest as well.
extension UnitTest {
    func XCTAssertSame(_ actual: [FlushPolicy], _ expected: [FlushPolicy], file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        // This is not the best way to compare arrays, but it's the best we can do for now without complicating the code.
        for index in actual.indices {
            // We assume if class types of policies are same, then policies are the same too.
            XCTAssertTrue(type(of: actual[index]) == type(of: expected[index]), file: file, line: line)
        }
    }

    func XCTAssertSame(_ actual: DispatchQueue?, _ expected: DispatchQueue, file: StaticString = #file, line: UInt = #line) {
        XCTAssertNotNil(actual)
        XCTAssertEqual(actual?.label, expected.label, file: file, line: line)
        XCTAssertEqual(actual?.qos, expected.qos, file: file, line: line)
    }
}
