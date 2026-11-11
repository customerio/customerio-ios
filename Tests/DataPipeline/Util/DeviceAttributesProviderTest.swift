@testable import CioDataPipelines
@testable import CioDataPipelinesMocks
@testable import CioInternalCommonMocks
@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class DeviceAttributesProviderTest: UnitTest {
    private let deviceInfoMock = DeviceInfoMock()
    private let sdkClientMock = SdkClientMock()
    private let apnsEnvironmentProviderMock = ApnsEnvironmentProviderMock()

    private var provider: SdkDeviceAttributesProvider!

    override func setUpDependencies() {
        super.setUpDependencies()

        mockCollection.add(mocks: [deviceInfoMock, sdkClientMock, apnsEnvironmentProviderMock])

        diGraphShared.override(value: provider, forType: DeviceAttributesProvider.self)
        diGraphShared.override(value: deviceInfoMock, forType: DeviceInfo.self)
        diGraphShared.override(value: sdkClientMock, forType: SdkClient.self)
    }

    override func setUp() {
        // do not call super.setUp() because we want to override SDK config and every test should
        // call setUp(modifySdkConfig:) to modify the SDK config before calling super.setUp()

        provider = SdkDeviceAttributesProvider(
            deviceInfo: deviceInfoMock,
            sdkClient: sdkClientMock,
            apnsEnvironmentProvider: apnsEnvironmentProviderMock
        )
    }

    func test_getDefaultDeviceAttributes_givenTrackingDeviceAttributesDisabled_expectEmptyAttributes() {
        super.setUp(modifySdkConfig: { config in
            config.autoTrackDeviceAttributes(false)
        })

        let expected: [String: String] = [:]

        let expect = expectation(description: "Expect to complete")
        provider.getDefaultDeviceAttributes { actual in
            XCTAssertEqual(actual as? [String: String], expected)

            expect.fulfill()
        }

        waitForExpectations()

        XCTAssertFalse(deviceInfoMock.mockCalled)
        XCTAssertFalse(apnsEnvironmentProviderMock.mockCalled)
    }

    func test_getDefaultDeviceAttributes_givenTrackingDeviceAttributesEnabled_expectGetSomeAttributes() {
        super.setUp(modifySdkConfig: { config in
            config.autoTrackDeviceAttributes(true)
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
        sdkClientMock.underlyingSource = "iOS"
        sdkClientMock.underlyingSdkVersion = givenSdkVersion
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

    func test_getDefaultDeviceAttributes_givenApnsEnvironmentKnown_expectApnsEnvironmentAttribute() {
        super.setUp(modifySdkConfig: { config in
            config.autoTrackDeviceAttributes(true)
        })
        stubDeviceInfo()

        for (givenEnvironment, expectedValue) in [(ApnsEnvironment.sandbox, "sandbox"), (.production, "production")] {
            apnsEnvironmentProviderMock.underlyingEnvironment = givenEnvironment

            let expect = expectation(description: "Expect to complete")
            provider.getDefaultDeviceAttributes { actual in
                XCTAssertEqual(actual["apns_environment"] as? String, expectedValue)

                expect.fulfill()
            }

            waitForExpectations()
        }
    }

    func test_getDefaultDeviceAttributes_givenApnsEnvironmentUnknown_expectNoApnsEnvironmentAttribute() {
        super.setUp(modifySdkConfig: { config in
            config.autoTrackDeviceAttributes(true)
        })
        stubDeviceInfo()
        apnsEnvironmentProviderMock.underlyingEnvironment = nil

        let expect = expectation(description: "Expect to complete")
        provider.getDefaultDeviceAttributes { actual in
            XCTAssertFalse(actual.keys.contains("apns_environment"))
            XCTAssertEqual(actual["push_enabled"] as? String, "true")

            expect.fulfill()
        }

        waitForExpectations()

        XCTAssertTrue(apnsEnvironmentProviderMock.environmentGetCalled)
    }

    private func stubDeviceInfo() {
        sdkClientMock.underlyingSdkVersion = String.random
        deviceInfoMock.underlyingCustomerAppVersion = String.random
        deviceInfoMock.underlyingDeviceLocale = String.random
        deviceInfoMock.underlyingDeviceManufacturer = String.random
        deviceInfoMock.isPushSubscribedClosure = { onComplete in
            onComplete(true)
        }
    }
}
