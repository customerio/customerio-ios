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
        let state = InAppMessageState(siteId: "test-site", publicKey: "pk_us_abc", dataCenter: "US")

        _ = ModalMessageManager(state: state, message: Message(messageId: "test-message"))

        XCTAssertEqual(engineWebProvider.lastConfiguration?.key, "pk_us_abc")
        XCTAssertEqual(engineWebProvider.lastConfiguration?.siteId, "test-site")
    }

    func test_messageManager_givenSiteIdOnly_expectNoKey() {
        let state = InAppMessageState(siteId: "test-site", dataCenter: "US")

        _ = ModalMessageManager(state: state, message: Message(messageId: "test-message"))

        XCTAssertNil(engineWebProvider.lastConfiguration?.key)
        XCTAssertEqual(engineWebProvider.lastConfiguration?.siteId, "test-site")
    }

    @MainActor
    func test_didFinish_givenKeyReplacedWhileLoading_expectCurrentKeyInjected() {
        let store = DIGraphShared.shared.backgroundDeliveryContextStore
        let state = InAppMessageState(siteId: "test-site", publicKey: "pk_us_old", dataCenter: "US")
        let message = Message(messageId: "test-message")
        let engine = EngineWeb(
            configuration: EngineWebConfiguration(
                siteId: "test-site",
                key: "pk_us_old",
                dataCenter: "US",
                instanceId: message.instanceId,
                endpoint: "https://engine",
                messageId: message.messageId,
                properties: nil
            ),
            state: state,
            message: message
        )
        defer { engine.cleanEngineWeb() }
        store.setCdpApiKey("pk_us_new")
        defer { store.setCdpApiKey(nil) }

        engine.webView(engine.webView, didFinish: nil)

        XCTAssertEqual(engine.currentConfiguration.key, "pk_us_new")
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
            key: "pk_us_abc",
            dataCenter: "US",
            instanceId: "instance",
            endpoint: "https://engine",
            messageId: "message",
            properties: nil
        )

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration)) as? [String: Any]

        XCTAssertEqual(json?["key"] as? String, "pk_us_abc")
        XCTAssertEqual(json?["siteId"] as? String, "test-site")
    }
}
