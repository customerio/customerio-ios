@testable import CioAnalytics
@testable import CioDataPipelines
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
        XCTAssertSame(dataPipelineConfig.flushPolicies, [CountBasedFlushPolicy(), IntervalBasedFlushPolicy()])
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
        let givenFlushPolicies: [FlushPolicy] = [CountBasedFlushPolicy(), IntervalBasedFlushPolicy()]
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
            .flushPolicies(givenFlushPolicies)
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
        XCTAssertSame(dataPipelineConfig.flushPolicies, givenFlushPolicies)
        XCTAssertEqual(dataPipelineConfig.trackApplicationLifecycleEvents, givenTrackApplicationLifecycleEvents)
        XCTAssertEqual(dataPipelineConfig.autoTrackDeviceAttributes, givenAutoTrackDeviceAttributes)
        XCTAssertEqual(dataPipelineConfig.migrationSiteId, givenSiteId)
        XCTAssertEqual(dataPipelineConfig.autoConfiguredPlugins.count, 0)
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
        let configuredPlugin = autoConfiguredPlugins.first
        // track screen to verify handlers are attached to the plugin.
        (configuredPlugin as? AutoTrackingScreenViews)?.performScreenTracking(onViewController: UIAlertController())

        XCTAssertEqual(autoConfiguredPlugins.count, 1)
        XCTAssertNotNil(configuredPlugin)
        XCTAssertTrue(configuredPlugin is AutoTrackingScreenViews)
        waitForExpectations()
    }

    func test_debugLogsEnabled_expectLoggerPluginAttached() {
        let (_, dataPipelineConfig) = SDKConfigBuilder(cdpApiKey: .random)
            .logLevel(.debug)
            .build()

        let autoConfiguredPlugins = dataPipelineConfig.autoConfiguredPlugins
        let configuredPlugin = autoConfiguredPlugins.first

        XCTAssertEqual(autoConfiguredPlugins.count, 1)
        XCTAssertNotNil(configuredPlugin)
        XCTAssertTrue(configuredPlugin is ConsoleLogger)
    }
}
