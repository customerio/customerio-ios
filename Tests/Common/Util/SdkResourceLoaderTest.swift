@testable import CioInternalCommon
import Foundation
import SharedTests
import XCTest

class SdkResourceLoaderTest: UnitTest {
    private var bundleDirectory: URL!

    override func setUp() {
        super.setUp()

        // Set up the temporary directory for tests
        bundleDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: bundleDirectory, withIntermediateDirectories: true, attributes: nil)
    }

    override func tearDown() {
        // Remove all files in temp directory by deleting the directory itself
        try? FileManager.default.removeItem(at: bundleDirectory)

        super.tearDown()
    }

    func test_loadPlist_returnsValidDictionary_whenPlistExists() {
        let mockPlistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleShortVersionString</key>
            <string>4.0.0</string>
        </dict>
        </plist>
        """
        let plistPath = bundleDirectory.appendingPathComponent("Info.plist")
        try? mockPlistContent.write(to: plistPath, atomically: true, encoding: .utf8)

        let bundle = Bundle(path: bundleDirectory.path)
        let sdkResourceLoader = CustomerIOResourceLoader(logger: diGraphShared.logger, bundle: bundle)
        let plist = sdkResourceLoader.loadPlist()

        guard let plist = plist else {
            XCTFail("Expected valid plist, but got nil")
            return
        }
        XCTAssertEqual(plist.count, 1)
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "4.0.0")
    }

    func test_loadClientInfoJson_returnsValidDictionary_whenJsonExists() {
        let mockJsonContent = """
        {
            "clientSource": "ReactNative",
            "clientVersion": "3.0.0"
        }
        """
        let jsonPath = bundleDirectory.appendingPathComponent("CIOClientInfo.json")
        try? mockJsonContent.write(to: jsonPath, atomically: true, encoding: .utf8)

        let bundle = Bundle(path: bundleDirectory.path)
        let sdkResourceLoader = CustomerIOResourceLoader(logger: diGraphShared.logger, bundle: bundle)
        let clientInfo = sdkResourceLoader.loadClientInfoJson()

        guard let clientInfo = clientInfo else {
            XCTFail("Expected valid clientInfo json, but got nil")
            return
        }
        XCTAssertEqual(clientInfo.count, 2)
        XCTAssertEqual(clientInfo["clientSource"] as? String, "ReactNative")
        XCTAssertEqual(clientInfo["clientVersion"] as? String, "3.0.0")
    }

    func test_createSdkClient_returnsValidClient_whenPlistAndJsonAreValid() {
        let sdkResourceLoaderMock = SdkResourceLoaderMock()
        sdkResourceLoaderMock.loadPlistReturnValue = ["CFBundleShortVersionString": "4.0.0"]
        sdkResourceLoaderMock.loadClientInfoJsonReturnValue = ["clientSource": "ReactNative", "clientVersion": "3.0.0"]

        let client = sdkResourceLoaderMock.resolveSdkClient()

        guard let client = client else {
            XCTFail("Expected valid SdkClient, but got nil")
            return
        }
        XCTAssertEqual(client.source, "ReactNative")
        XCTAssertEqual(client.sdkVersion, "3.0.0")
    }

    func test_createSdkClient_returnsValidClient_whenClientVersionIsMissingInPlist() {
        let sdkResourceLoaderMock = SdkResourceLoaderMock()
        sdkResourceLoaderMock.loadPlistReturnValue = nil
        sdkResourceLoaderMock.loadClientInfoJsonReturnValue = ["clientSource": "ReactNative", "clientVersion": "3.0.0"]

        let client = sdkResourceLoaderMock.resolveSdkClient()

        guard let client = client else {
            XCTFail("Expected valid SdkClient, but got nil")
            return
        }
        XCTAssertEqual(client.source, "ReactNative")
        XCTAssertEqual(client.sdkVersion, "3.0.0")
    }

    func test_createSdkClient_fallsBackToPlist_whenClientVersionIsMissingInJson() {
        let sdkResourceLoaderMock = SdkResourceLoaderMock()
        sdkResourceLoaderMock.loadPlistReturnValue = ["CFBundleShortVersionString": "4.0.0"]
        sdkResourceLoaderMock.loadClientInfoJsonReturnValue = ["clientSource": "ReactNative"]

        let client = sdkResourceLoaderMock.resolveSdkClient()

        guard let client = client else {
            XCTFail("Expected valid SdkClient, but got nil")
            return
        }
        XCTAssertEqual(client.source, "ReactNative")
        XCTAssertEqual(client.sdkVersion, "4.0.0")
    }

    func test_createSdkClient_returnsNil_whenClientSourceIsMissing() {
        let sdkResourceLoaderMock = SdkResourceLoaderMock()
        sdkResourceLoaderMock.loadPlistReturnValue = ["CFBundleShortVersionString": "4.0.0"]
        sdkResourceLoaderMock.loadClientInfoJsonReturnValue = ["clientVersion": "3.0.0"]

        let client = sdkResourceLoaderMock.resolveSdkClient()

        XCTAssertNil(client)
    }

    func test_createSdkClient_returnsNil_whenPlistAndJsonAreInvalid() {
        let sdkResourceLoaderMock = SdkResourceLoaderMock()
        sdkResourceLoaderMock.loadPlistReturnValue = ["CFBundleVersionString": "4.0.0"]
        sdkResourceLoaderMock.loadClientInfoJsonReturnValue = ["source": "ReactNative", "version": "3.0.0"]

        let client = sdkResourceLoaderMock.resolveSdkClient()

        XCTAssertNil(client)
    }

    func test_createSdkClient_returnsNil_whenPlistAndJsonAreEmpty() {
        let sdkResourceLoaderMock = SdkResourceLoaderMock()
        sdkResourceLoaderMock.loadPlistReturnValue = [:]
        sdkResourceLoaderMock.loadClientInfoJsonReturnValue = [:]

        let client = sdkResourceLoaderMock.resolveSdkClient()

        XCTAssertNil(client)
    }

    func test_createSdkClient_returnsNil_whenPlistAndJsonAreNil() {
        let sdkResourceLoaderMock = SdkResourceLoaderMock()
        sdkResourceLoaderMock.loadPlistReturnValue = nil
        sdkResourceLoaderMock.loadClientInfoJsonReturnValue = nil

        let client = sdkResourceLoaderMock.resolveSdkClient()

        XCTAssertNil(client)
    }
}
