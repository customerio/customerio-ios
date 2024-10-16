@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class SdkClientTest: UnitTest {
    private let deviceInfoMock = DeviceInfoMock()
    private let defaultClientString = "iOS Client/\(SdkVersion.version)"

    private func createClientString(source: String, sdkVersion: String) -> String {
        CustomerIOSdkClient(source: source, sdkVersion: sdkVersion).description
    }

    override func setUpDependencies() {
        super.setUpDependencies()

        diGraphShared.override(value: deviceInfoMock, forType: DeviceInfo.self)
    }

    // MARK: - Valid Inputs

    func test_givenClientAsString_expectCorrectDescription() {
        let expected = "iOS Client/2.0.0"

        let actual = "\(CustomerIOSdkClient(source: "iOS", sdkVersion: "2.0.0"))"

        XCTAssertEqual(expected, actual)
    }

    func test_givenCustomOS_expectMatchingDescription() {
        let givenSource = "TestOS"
        let expected = "\(givenSource) Client/\(SdkVersion.version)"

        deviceInfoMock.underlyingOsName = givenSource
        let actual = diGraphShared.customSdkClient.description

        XCTAssertEqual(expected, actual)
    }

    func test_givenValidSourceAndSdkVersion_expectMatchingDescription() {
        let expected = "React Native Client/2.0.0"

        let actual = createClientString(source: "React Native", sdkVersion: "2.0.0")

        XCTAssertEqual(expected, actual)
    }

    // MARK: - Missing or Empty Values

    func test_givenEmptySource_expectDefaultClient() {
        let actual = createClientString(source: "", sdkVersion: "2.0.0")

        XCTAssertEqual(defaultClientString, actual)
    }

    func test_givenEmptySdkVersion_expectDefaultClient() {
        let actual = createClientString(source: "React Native", sdkVersion: "")

        XCTAssertEqual(defaultClientString, actual)
    }

    // MARK: - Both Nil or Empty Values

    func test_givenEmptySourceAndSdkVersion_expectDefaultClient() {
        let actual = createClientString(source: "", sdkVersion: "")

        XCTAssertEqual(defaultClientString, actual)
    }
}
