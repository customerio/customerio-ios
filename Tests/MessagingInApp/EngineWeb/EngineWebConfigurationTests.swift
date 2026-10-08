@testable import CioInternalCommon
@testable import CioMessagingInApp
@testable import CioMessagingInAppMocks
import Foundation
import SharedTests
import XCTest

class EngineWebConfigurationTests: UnitTest {
    private let engineWebMock = EngineWebInstanceMock()
    private var engineWebProvider: EngineWebProviderStub!

    override func setUp() {
        super.setUp()
        engineWebMock.underlyingView = UIView()
        engineWebProvider = EngineWebProviderStub(engineWebMock: engineWebMock)
        mockCollection.add(mock: engineWebMock)
        diGraphShared.override(value: engineWebProvider, forType: EngineWebProvider.self)
    }

    func test_messageManager_givenPublicKey_expectKeyPassedToEngine() {
        let state = InAppMessageState(siteId: "test-site", publicKey: "wk_us_abc", dataCenter: "US")

        _ = ModalMessageManager(state: state, message: Message(messageId: "test-message"))

        XCTAssertEqual(engineWebProvider.lastConfiguration?.key, "wk_us_abc")
        XCTAssertEqual(engineWebProvider.lastConfiguration?.siteId, "test-site")
    }

    func test_messageManager_givenSiteIdOnly_expectNoKey() {
        let state = InAppMessageState(siteId: "test-site", dataCenter: "US")

        _ = ModalMessageManager(state: state, message: Message(messageId: "test-message"))

        XCTAssertNil(engineWebProvider.lastConfiguration?.key)
        XCTAssertEqual(engineWebProvider.lastConfiguration?.siteId, "test-site")
    }

    func test_encode_givenNoKey_expectKeyOmitted() throws {
        let configuration = EngineWebConfiguration(
            siteId: "test-site",
            dataCenter: "US",
            instanceId: "instance",
            endpoint: "https://engine",
            messageId: "message",
            properties: nil
        )

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration)) as? [String: Any]

        XCTAssertEqual(json?["siteId"] as? String, "test-site")
        XCTAssertNil(json?["key"])
    }

    func test_encode_givenKey_expectKeyEncoded() throws {
        let configuration = EngineWebConfiguration(
            siteId: "test-site",
            key: "wk_us_abc",
            dataCenter: "US",
            instanceId: "instance",
            endpoint: "https://engine",
            messageId: "message",
            properties: nil
        )

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration)) as? [String: Any]

        XCTAssertEqual(json?["key"] as? String, "wk_us_abc")
        XCTAssertEqual(json?["siteId"] as? String, "test-site")
    }
}
