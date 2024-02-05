@testable import CioDataPipelines
@testable import CioInternalCommon
@testable import CioTracking
import Foundation
import SharedTests
import XCTest

class DeviceAttributesProviderTest: IntegrationTest {
    private let deviceInfoMock = DeviceInfoMock()

    private var provider: SdkDeviceAttributesProvider!

    override func setUpDependencies() {
        super.setUpDependencies()

        provider = SdkDeviceAttributesProvider(deviceInfo: deviceInfoMock)

        diGraphShared.override(value: provider, forType: DeviceAttributesProvider.self)
        diGraph.override(value: provider, forType: DeviceAttributesProvider.self)
        diGraphShared.override(value: deviceInfoMock, forType: DeviceInfo.self)
        diGraph.override(value: deviceInfoMock, forType: DeviceInfo.self)
    }

    override func setUp() {
        // do not call super.setUp() because we want to override SDK config and every test should
        // call setUp(modifySdkConfig:) to modify the SDK config before calling super.setUp()
    }

    func test_getDefaultDeviceAttributes_givenTrackingDeviceAttributesDisabled_expectEmptyAttributes() {
        super.setUp(modifySdkConfig: { config in
            config.autoTrackDeviceAttributes = false
        })

        let expected: [String: String] = [:]

        let expect = expectation(description: "Expect to complete")
        provider.getDefaultDeviceAttributes { actual in
            XCTAssertEqual(actual as? [String: String], expected)

            expect.fulfill()
        }

        waitForExpectations()

        XCTAssertFalse(deviceInfoMock.mockCalled)
    }

    func test_getDefaultDeviceAttributes_givenTrackingDeviceAttributesEnabled_expectGetSomeAttributes() {
        super.setUp(modifySdkConfig: { config in
            config.autoTrackDeviceAttributes = true
        })

        let givenSdkVersion = String.random
        let givenAppVersion = String.random
        let givenDeviceLocale = String.random
        let givenDeviceManufacturer = String.random
        let expected = [
            "cio_sdk_version": givenSdkVersion,
            "app_version": givenAppVersion,
            "device_locale": givenDeviceLocale,
            "push_enabled": "true",
            "device_manufacturer": givenDeviceManufacturer
        ]
        deviceInfoMock.underlyingSdkVersion = givenSdkVersion
        deviceInfoMock.underlyingCustomerAppVersion = givenAppVersion
        deviceInfoMock.underlyingDeviceLocale = givenDeviceLocale
        deviceInfoMock.underlyingDeviceManufacturer = givenDeviceManufacturer
        deviceInfoMock.isPushSubscribedClosure = { onComplete in
            onComplete(true)
        }

        let expect = expectation(description: "Expect to complete")
        provider.getDefaultDeviceAttributes { actual in
            XCTAssertEqual(actual as? [String: String], expected)

            expect.fulfill()
        }

        waitForExpectations()
    }
}
