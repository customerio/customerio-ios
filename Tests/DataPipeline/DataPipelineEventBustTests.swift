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

        mockCollection.add(mocks: [deviceAttributesMock, globalDataStoreMock])

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

    func testSubscribeToJourneyEvents_DataPipelineHandlesTrackGeofenceMetricEvent_enter() async {
        let givenGeofenceId = String.random
        let capturedAt = Date(timeIntervalSince1970: 1700000000)

        await eventBusHandler.postEventAndWait(
            TrackGeofenceMetricEvent(
                geofenceId: givenGeofenceId,
                transition: .enter,
                timestamp: capturedAt
            )
        )

        guard let trackEvent = outputReader.lastEvent as? TrackEvent else {
            XCTFail("recorded event is not an instance of TrackEvent")
            return
        }

        XCTAssertEqual(trackEvent.type, "track")
        XCTAssertEqual(trackEvent.event, "CIO Geofence Entered")
        let properties = trackEvent.properties?.dictionaryValue ?? [:]
        XCTAssertEqual(properties["geofence_id"] as? String, givenGeofenceId)
        XCTAssertEqual(properties["transition_type"] as? String, "enter")
        XCTAssertEqual(properties["timestamp"] as? Int, Int(capturedAt.timeIntervalSince1970))
        XCTAssertNil(properties["latitude"])
        XCTAssertNil(properties["longitude"])
        XCTAssertEqual(trackEvent.timestamp, capturedAt.string(format: .iso8601WithMilliseconds))
    }

    func testSubscribeToJourneyEvents_DataPipelineHandlesTrackGeofenceMetricEvent_exit() async {
        let givenGeofenceId = String.random
        let capturedAt = Date(timeIntervalSince1970: 1700000000)

        await eventBusHandler.postEventAndWait(
            TrackGeofenceMetricEvent(
                geofenceId: givenGeofenceId,
                transition: .exit,
                timestamp: capturedAt
            )
        )

        guard let trackEvent = outputReader.lastEvent as? TrackEvent else {
            XCTFail("recorded event is not an instance of TrackEvent")
            return
        }

        XCTAssertEqual(trackEvent.event, "CIO Geofence Exited")
        let properties = trackEvent.properties?.dictionaryValue ?? [:]
        XCTAssertEqual(properties["geofence_id"] as? String, givenGeofenceId)
        XCTAssertEqual(properties["transition_type"] as? String, "exit")
        XCTAssertEqual(properties["timestamp"] as? Int, Int(capturedAt.timeIntervalSince1970))
        XCTAssertNil(properties["latitude"])
        XCTAssertNil(properties["longitude"])
        XCTAssertEqual(trackEvent.timestamp, capturedAt.string(format: .iso8601WithMilliseconds))
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

    func testGetOptionalDataPipelineTracking_returnsImplementationAndTrackSendsToAnalytics() {
        // DataPipeline registers as DataPipelineTracking on init; Location (and others) resolve via getOptional.
        let pipeline = diGraphShared.getOptional(DataPipelineTracking.self)
        XCTAssertNotNil(pipeline, "DataPipelineTracking should be registered after DataPipeline init")

        customerIO.identify(userId: String.random)

        let givenLatitude = 37.7749
        let givenLongitude = -122.4194
        pipeline?.track(
            name: "CIO Location Update",
            properties: ["latitude": givenLatitude, "longitude": givenLongitude]
        )

        guard let trackEvent = outputReader.lastEvent as? TrackEvent else {
            XCTFail("recorded event is not an instance of TrackEvent")
            return
        }

        XCTAssertEqual(trackEvent.type, "track")
        XCTAssertEqual(trackEvent.event, "CIO Location Update")

        let properties = trackEvent.properties?.dictionaryValue
        XCTAssertEqual(properties?["latitude"] as? Double, givenLatitude)
        XCTAssertEqual(properties?["longitude"] as? Double, givenLongitude)
    }
}
