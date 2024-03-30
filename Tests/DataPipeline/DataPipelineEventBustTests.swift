@testable import CioAnalytics
@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
@testable import SharedTests
import XCTest

class DataPipelineEventBustTests: IntegrationTest {
    var outputReader: OutputReaderPlugin!

    private var eventBusHandler: EventBusHandler {
        diGraphShared.eventBusHandler
    }

    private let deviceAttributesMock = DeviceAttributesProviderMock()
    private let globalDataStoreMock = GlobalDataStoreMock()

    override func setUpDependencies() {
        super.setUpDependencies()

        diGraphShared.override(value: deviceAttributesMock, forType: DeviceAttributesProvider.self)
        diGraphShared.override(value: globalDataStoreMock, forType: GlobalDataStore.self)
    }

    override func setUp() {
        super.setUp(modifySdkConfig: nil)
        // OutputReaderPlugin helps validating interactions with analytics
        outputReader = (customerIO.add(plugin: OutputReaderPlugin()) as? OutputReaderPlugin)
    }

    func testSubscribeToJourneyEvents_DataPipelineHandlesTrackMetricEvent() async {
        let givenDeliveryID = String.random
        let givenMetric = Metric.delivered.rawValue
        let givenDeviceToken = String.random

        let givenMetricEvent = TrackMetricEvent(deliveryID: givenDeliveryID, event: givenMetric, deviceToken: givenDeviceToken)

        await eventBusHandler.postEventAndWait(givenMetricEvent)

        let expectedData: [String: Any] = [
            "metric": givenMetric,
            "deliveryId": givenDeliveryID,
            "recipient": givenDeviceToken
        ]

        guard let trackEvent = outputReader.lastEvent as? TrackEvent else {
            XCTFail("recorded event is not an instance of TrackEvent")
            return
        }

        XCTAssertEqual(trackEvent.type, "track")
        XCTAssertEqual(trackEvent.event, "Report Delivery Event")
        XCTAssertMatches(
            trackEvent.properties,
            expectedData
        )
    }

    func testSubscribeToJourneyEvents_DataPipelineHandlesRegisterDeviceEvent() async {
        let givenToken = String.random

        let givenRegisterEvent = RegisterDeviceTokenEvent(token: givenToken)

        deviceAttributesMock.getDefaultDeviceAttributesClosure = { $0([:]) }

        await eventBusHandler.postEventAndWait(givenRegisterEvent)

        guard let trackEvent = outputReader.lastEvent as? TrackEvent else {
            XCTFail("recorded event is not an instance of TrackEvent")
            return
        }

        XCTAssertEqual(trackEvent.type, "track")
        XCTAssertEqual(trackEvent.event, "Device Created or Updated")
        XCTAssertEqual(trackEvent.deviceToken, givenToken)
    }
}
