@testable import CioDataPipelines
@testable import Segment
import SharedTests
import XCTest

class SDKConfigBuilderTest: UnitTest {
    func test_initializeAndDoNotModify_expectDefaultValues() {
        let (sdkConfig, dataPipelineConfig) = SDKConfigBuilder(cdpApiKey: .random).build()

        XCTAssertEqual(sdkConfig.logLevel, .error)

        XCTAssertEqual(dataPipelineConfig.apiHost, "cdp.customer.io/v1")
        XCTAssertEqual(dataPipelineConfig.cdnHost, "cdp.customer.io/v1")
        XCTAssertEqual(dataPipelineConfig.flushAt, 20)
        XCTAssertEqual(dataPipelineConfig.flushInterval, 30.0)
        XCTAssertTrue(dataPipelineConfig.autoAddCustomerIODestination)
        XCTAssertNil(dataPipelineConfig.defaultSettings)
        XCTAssertSame(dataPipelineConfig.flushPolicies, [CountBasedFlushPolicy(), IntervalBasedFlushPolicy()])
        XCTAssertSame(dataPipelineConfig.flushQueue, DispatchQueue(label: "com.segment.operatingModeQueue", qos: .utility))
        XCTAssertEqual(dataPipelineConfig.operatingMode, OperatingMode.asynchronous)
        XCTAssertTrue(dataPipelineConfig.trackApplicationLifecycleEvents)
        XCTAssertTrue(dataPipelineConfig.autoTrackDeviceAttributes)
        XCTAssertNil(dataPipelineConfig.migrationSiteId)
        XCTAssertEqual(dataPipelineConfig.autoConfiguredPlugins.count, 0)
    }

    func test_initializeAndModify_expectCustomValues() {
        let givenLogLevel = CioLogLevel.info

        let givenCdpApiKey = String.random
        let givenApiHost = String.random
        let givenCdnHost = String.random
        let givenFlushAt = 17
        let givenFlushInterval = 23.7
        let givenAutoAddCustomerIODestination = false
        let givenSettings = Settings(writeKey: givenCdpApiKey)
        let givenFlushPolicies: [FlushPolicy] = [CountBasedFlushPolicy(), IntervalBasedFlushPolicy()]
        let givenFlushQueue = DispatchQueue(label: "com.segment.operatingModeQueue", qos: .utility)
        let givenOperatingMode = OperatingMode.synchronous
        let givenTrackApplicationLifecycleEvents = false
        let givenAutoTrackDeviceAttributes = false
        let givenSiteId = String.random

        let (sdkConfig, dataPipelineConfig) = SDKConfigBuilder(cdpApiKey: givenCdpApiKey)
            .logLevel(givenLogLevel)
            // Region should be ignored because we are setting the API host and CDN host directly.
            .region(.US)
            .apiHost(givenApiHost)
            .cdnHost(givenCdnHost)
            .flushAt(givenFlushAt)
            .flushInterval(givenFlushInterval)
            .autoAddCustomerIODestination(givenAutoAddCustomerIODestination)
            .defaultSettings(givenSettings)
            .flushPolicies(givenFlushPolicies)
            .flushQueue(givenFlushQueue)
            .operatingMode(givenOperatingMode)
            .trackApplicationLifecycleEvents(givenTrackApplicationLifecycleEvents)
            .autoTrackDeviceAttributes(givenAutoTrackDeviceAttributes)
            .autoTrackUIKitScreenViews(enabled: false)
            .migrationSiteId(givenSiteId)
            .build()

        XCTAssertEqual(sdkConfig.logLevel, givenLogLevel)

        XCTAssertEqual(dataPipelineConfig.cdpApiKey, givenCdpApiKey)
        XCTAssertEqual(dataPipelineConfig.apiHost, givenApiHost)
        XCTAssertEqual(dataPipelineConfig.cdnHost, givenCdnHost)
        XCTAssertEqual(dataPipelineConfig.flushAt, givenFlushAt)
        XCTAssertEqual(dataPipelineConfig.flushInterval, givenFlushInterval)
        XCTAssertEqual(dataPipelineConfig.autoAddCustomerIODestination, givenAutoAddCustomerIODestination)
        XCTAssertSame(dataPipelineConfig.defaultSettings, givenSettings)
        XCTAssertSame(dataPipelineConfig.flushPolicies, givenFlushPolicies)
        XCTAssertSame(dataPipelineConfig.flushQueue, givenFlushQueue)
        XCTAssertEqual(dataPipelineConfig.operatingMode, givenOperatingMode)
        XCTAssertEqual(dataPipelineConfig.trackApplicationLifecycleEvents, givenTrackApplicationLifecycleEvents)
        XCTAssertEqual(dataPipelineConfig.autoTrackDeviceAttributes, givenAutoTrackDeviceAttributes)
        XCTAssertEqual(dataPipelineConfig.migrationSiteId, givenSiteId)
        XCTAssertEqual(dataPipelineConfig.autoConfiguredPlugins.count, 0)
    }

    func test_givenDefaults_expectMatchAnalyticsDefaults() {
        let givenCdpApiKey = String.random
        let analyticsConfig = Configuration(writeKey: givenCdpApiKey).values

        var analyticsDefaultExpectedSettings = Settings(writeKey: givenCdpApiKey)
        do {
            analyticsDefaultExpectedSettings.integrations = try JSON(["Segment.io": true])
        } catch {
            XCTFail("Failed to setup test integrations with error: \(error)")
        }

        let (_, actual) = SDKConfigBuilder(cdpApiKey: .random).build()

        // API host and CDN host should match Customer.io's CDP settings.
        XCTAssertEqual(actual.apiHost, "cdp.customer.io/v1")
        XCTAssertEqual(actual.cdnHost, "cdp.customer.io/v1")
        // Remaining values should match the analytics configuration.
        XCTAssertEqual(actual.flushAt, analyticsConfig.flushAt)
        XCTAssertEqual(actual.flushInterval, analyticsConfig.flushInterval)
        XCTAssertEqual(actual.autoAddCustomerIODestination, analyticsConfig.autoAddSegmentDestination)
        XCTAssertNil(actual.defaultSettings)
        XCTAssertSame(analyticsConfig.defaultSettings, analyticsDefaultExpectedSettings)
        XCTAssertSame(actual.flushPolicies, analyticsConfig.flushPolicies)
        XCTAssertSame(actual.flushQueue, analyticsConfig.flushQueue)
        XCTAssertEqual(actual.operatingMode, analyticsConfig.operatingMode)
        XCTAssertEqual(actual.trackApplicationLifecycleEvents, analyticsConfig.trackApplicationLifecycleEvents)
    }

    func test_givenRegionUS_expectRegionDefaults() {
        let (_, dataPipelineConfig) = SDKConfigBuilder(cdpApiKey: .random)
            .region(.US)
            .build()

        XCTAssertEqual(dataPipelineConfig.apiHost, "cdp.customer.io/v1")
        XCTAssertEqual(dataPipelineConfig.cdnHost, "cdp.customer.io/v1")
    }

    func test_givenRegionEU_expectRegionDefaults() {
        let (_, dataPipelineConfig) = SDKConfigBuilder(cdpApiKey: .random)
            .region(.EU)
            .build()

        XCTAssertEqual(dataPipelineConfig.apiHost, "cdp-eu.customer.io/v1")
        XCTAssertEqual(dataPipelineConfig.cdnHost, "cdp-eu.customer.io/v1")
    }

    func test_givenApiHostModified_expectIgnoreRegionDefaultsForApiHost() {
        let givenApiHost = String.random

        let (_, dataPipelineConfig) = SDKConfigBuilder(cdpApiKey: .random)
            .region(.US)
            .apiHost(givenApiHost)
            .build()

        XCTAssertEqual(dataPipelineConfig.apiHost, givenApiHost)
        XCTAssertEqual(dataPipelineConfig.cdnHost, "cdp.customer.io/v1")
    }

    func test_givenCdnHostModified_expectIgnoreRegionDefaultsForCdnHost() {
        let givenCdnHost = String.random

        let (_, dataPipelineConfig) = SDKConfigBuilder(cdpApiKey: .random)
            .region(.US)
            .cdnHost(givenCdnHost)
            .build()

        XCTAssertEqual(dataPipelineConfig.apiHost, "cdp.customer.io/v1")
        XCTAssertEqual(dataPipelineConfig.cdnHost, givenCdnHost)
    }

    func test_autoScreenTrackingEnabled_expectScreenPluginAttachedWithGivenHandlers() {
        let autoScreenViewBodyExpectation = expectation(description: "Waiting for autoScreenViewBody to be invoked")
        let givenAutoScreenViewBody: (() -> [String: Any]) = {
            autoScreenViewBodyExpectation.fulfill()
            return [:]
        }

        let filterAutoScreenViewEventsExpectation = expectation(description: "Waiting for filterAutoScreenViewEvents to be invoked")
        let givenFilterAutoScreenViewEvents: ((UIViewController) -> Bool) = { _ in
            filterAutoScreenViewEventsExpectation.fulfill()
            return true
        }

        let (_, dataPipelineConfig) = SDKConfigBuilder(cdpApiKey: .random)
            .autoTrackUIKitScreenViews(
                enabled: true,
                autoScreenViewBody: givenAutoScreenViewBody,
                filterAutoScreenViewEvents: givenFilterAutoScreenViewEvents
            )
            .build()

        let autoConfiguredPlugins = dataPipelineConfig.autoConfiguredPlugins
        let screenPlugin = autoConfiguredPlugins.first
        // track screen to verify handlers are attached to the plugin.
        (screenPlugin as? AutoTrackingScreenViews)?.performScreenTracking(onViewController: UIAlertController())

        XCTAssertEqual(autoConfiguredPlugins.count, 1)
        XCTAssertNotNil(screenPlugin)
        XCTAssertTrue(screenPlugin is AutoTrackingScreenViews)
        waitForExpectations()
    }
}

/// Helper methods to assert custom types.
extension SDKConfigBuilderTest {
    func XCTAssertSame(_ actual: Settings?, _ expected: Settings, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(actual?.integrations, expected.integrations, file: file, line: line)
    }

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
