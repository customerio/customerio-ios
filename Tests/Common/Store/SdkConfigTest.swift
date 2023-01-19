@testable import Common
import Foundation
import SharedTests
import XCTest

class SdkConfigTest: UnitTest {
    func test_httpBaseUrl_givenUrls_expectGetCorrectlyMappedValues() {
        let givenTrackingUrl = String.random
        let expected = HttpBaseUrls(trackingApi: givenTrackingUrl)

        let actual = SdkConfig(trackingApiUrl: givenTrackingUrl).httpBaseUrls

        XCTAssertEqual(actual, expected)
    }

    func test_sdkConfigMapping_givenConfigParamsMap_expectCorrectlyMappedConfigValues() {
        let givenConfigMap = [
            SdkConfig.Config.backgroundQueueMinNumberOfTasks: 3,
            SdkConfig.Config.backgroundQueueSecondsDelay: 30,
            SdkConfig.Config.autoTrackPushEvents: false,
            SdkConfig.Config.logLevel: 1
        ] as [String: Any]

        let expectedConfig = SdkConfig.Factory.create(region: Region.US, params: givenConfigMap)

        let actualSdkConfig = SdkConfig(trackingApiUrl: Region.US.productionTrackingUrl, autoTrackPushEvents: false, backgroundQueueMinNumberOfTasks: 3, backgroundQueueSecondsDelay: 30, logLevel: CioLogLevel.none)

        XCTAssertEqual(expectedConfig.backgroundQueueMinNumberOfTasks, actualSdkConfig.backgroundQueueMinNumberOfTasks)
        XCTAssertEqual(expectedConfig.trackingApiUrl, actualSdkConfig.trackingApiUrl)
        XCTAssertEqual(expectedConfig.autoTrackPushEvents, actualSdkConfig.autoTrackPushEvents)
        XCTAssertEqual(expectedConfig.backgroundQueueSecondsDelay, actualSdkConfig.backgroundQueueSecondsDelay)
        XCTAssertEqual(expectedConfig.logLevel, actualSdkConfig.logLevel)
    }

    func test_sdkConfigMapping_givenDifferentConfigParams_expectCorrectlyMappedConfigValues() {
        let givenConfigMap = [
            SdkConfig.Config.trackingApiUrl: "tracking",
            SdkConfig.Config.backgroundQueueMinNumberOfTasks: 8,
            SdkConfig.Config.backgroundQueueSecondsDelay: 120,
            SdkConfig.Config.autoTrackPushEvents: false,
            SdkConfig.Config.logLevel: "none"
        ] as [String: Any]

        let expectedConfig = SdkConfig.Factory.create(region: Region.EU, params: givenConfigMap)

        let actualSdkConfig = SdkConfig(trackingApiUrl: "tracking", autoTrackPushEvents: false, backgroundQueueMinNumberOfTasks: 8, backgroundQueueSecondsDelay: 120, logLevel: CioLogLevel.none)

        XCTAssertEqual(expectedConfig.backgroundQueueMinNumberOfTasks, actualSdkConfig.backgroundQueueMinNumberOfTasks)
        XCTAssertEqual(expectedConfig.trackingApiUrl, actualSdkConfig.trackingApiUrl)
        XCTAssertEqual(expectedConfig.autoTrackPushEvents, actualSdkConfig.autoTrackPushEvents)
        XCTAssertEqual(expectedConfig.backgroundQueueSecondsDelay, actualSdkConfig.backgroundQueueSecondsDelay)
        XCTAssertEqual(expectedConfig.logLevel, actualSdkConfig.logLevel)
    }

    func test_sdkConfigMapping_givenReactPackageConfigParams_expectCorrectlyMappedConfigValues() {
        let givenConfigMap = [
            SdkConfig.Package.source: SdkWrapperConfig.Source.reactNative.rawValue,
            SdkConfig.Package.sourceVersion: "1.1.1"
        ] as [String: Any]

        let expectedConfig = SdkConfig.Factory.create(region: Region.EU, params: givenConfigMap)

        let actualSdkConfig = SdkConfig(trackingApiUrl: "tracking", _sdkWrapperConfig: SdkWrapperConfig(source: SdkWrapperConfig.Source.reactNative, version: "1.1.1"))

        XCTAssertEqual(expectedConfig._sdkWrapperConfig?.source, actualSdkConfig._sdkWrapperConfig?.source)
        XCTAssertEqual(expectedConfig._sdkWrapperConfig?.version, actualSdkConfig._sdkWrapperConfig?.version)
    }

    func test_sdkConfigMapping_givenFlutterPackageConfigParams_expectCorrectlyMappedConfigValues() {
        let givenConfigMap = [
            SdkConfig.Package.source: SdkWrapperConfig.Source.flutter.rawValue,
            SdkConfig.Package.sourceVersion: "3.2.1"
        ] as [String: Any]

        let expectedConfig = SdkConfig.Factory.create(region: Region.EU, params: givenConfigMap)

        let actualSdkConfig = SdkConfig(trackingApiUrl: "tracking", _sdkWrapperConfig: SdkWrapperConfig(source: SdkWrapperConfig.Source.flutter, version: "3.2.1"))

        XCTAssertEqual(expectedConfig._sdkWrapperConfig?.source, actualSdkConfig._sdkWrapperConfig?.source)
        XCTAssertEqual(expectedConfig._sdkWrapperConfig?.version, actualSdkConfig._sdkWrapperConfig?.version)
    }

    func test_sdkConfigMapping_givenWrongPackageSourceConfigParams_expectCorrectlyMappedConfigValues() {
        let givenConfigMap = [
            SdkConfig.Package.source: "Dummy",
            SdkConfig.Package.sourceVersion: "3.2.1"
        ] as [String: Any]

        let expectedConfig = SdkConfig.Factory.create(region: Region.EU, params: givenConfigMap)

        let actualSdkConfig = SdkConfig(trackingApiUrl: "tracking")

        XCTAssertEqual(expectedConfig._sdkWrapperConfig?.source, actualSdkConfig._sdkWrapperConfig?.source)
        XCTAssertEqual(expectedConfig._sdkWrapperConfig?.version, actualSdkConfig._sdkWrapperConfig?.version)
    }

    func test_sdkConfigMapping_givenWrongPackageSourceVersionConfigParams_expectCorrectlyMappedConfigValues() {
        let givenConfigMap = [
            SdkConfig.Package.source: "Dummy"
        ] as [String: Any]

        let expectedConfig = SdkConfig.Factory.create(region: Region.EU, params: givenConfigMap)

        let actualSdkConfig = SdkConfig(trackingApiUrl: "tracking")

        XCTAssertEqual(expectedConfig._sdkWrapperConfig?.source, actualSdkConfig._sdkWrapperConfig?.source)
        XCTAssertEqual(expectedConfig._sdkWrapperConfig?.version, actualSdkConfig._sdkWrapperConfig?.version)
    }
}
