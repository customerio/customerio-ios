@testable import CioAnalytics
@testable import CioDataPipelinesMocks
@testable import CioInternalCommonMocks
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
    private let dataPipelinesLoggerMock = DataPipelinesLoggerMock()

    override func setUpDependencies() {
        super.setUpDependencies()

        mockCollection.add(mocks: [deviceAttributesMock, globalDataStoreMock, dataPipelinesLoggerMock])

        diGraphShared.override(value: deviceAttributesMock, forType: DeviceAttributesProvider.self)
        diGraphShared.override(value: globalDataStoreMock, forType: GlobalDataStore.self)
        diGraphShared.override(value: dataPipelinesLoggerMock, forType: DataPipelinesLogger.self)
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
                timestamp: capturedAt,
                name: "HQ",
                transitionId: "txn_enter_1",
                userId: "user_1"
            )
        )

        guard let trackEvent = outputReader.lastEvent as? TrackEvent else {
            XCTFail("recorded event is not an instance of TrackEvent")
            return
        }

        XCTAssertEqual(trackEvent.type, "track")
        XCTAssertEqual(trackEvent.event, "Geofence Transition")
        let properties = trackEvent.properties?.dictionaryValue ?? [:]
        XCTAssertEqual(properties["geofenceId"] as? String, givenGeofenceId)
        XCTAssertEqual(properties["transition"] as? String, "enter")
        XCTAssertEqual(properties["geofenceName"] as? String, "HQ")
        // timestamp lives on the event envelope, not in properties.
        XCTAssertNil(properties["timestamp"])
        XCTAssertNil(properties["latitude"])
        XCTAssertNil(properties["longitude"])
        XCTAssertEqual(trackEvent.timestamp, capturedAt.string(format: .iso8601WithMilliseconds))
        // EventBus path carries the transitionId through to the analytics payload.
        XCTAssertEqual(properties["transitionId"] as? String, "txn_enter_1")
    }

    func testSubscribeToJourneyEvents_DataPipelineHandlesTrackGeofenceMetricEvent_exit() async {
        let givenGeofenceId = String.random
        let capturedAt = Date(timeIntervalSince1970: 1700000000)

        await eventBusHandler.postEventAndWait(
            TrackGeofenceMetricEvent(
                geofenceId: givenGeofenceId,
                transition: .exit,
                timestamp: capturedAt,
                name: nil,
                transitionId: "txn_exit_1",
                userId: "user_1"
            )
        )

        guard let trackEvent = outputReader.lastEvent as? TrackEvent else {
            XCTFail("recorded event is not an instance of TrackEvent")
            return
        }

        XCTAssertEqual(trackEvent.event, "Geofence Transition")
        let properties = trackEvent.properties?.dictionaryValue ?? [:]
        XCTAssertEqual(properties["geofenceId"] as? String, givenGeofenceId)
        XCTAssertEqual(properties["transition"] as? String, "exit")
        // No name on the event → property omitted entirely.
        XCTAssertNil(properties["geofenceName"])
        // timestamp lives on the event envelope, not in properties.
        XCTAssertNil(properties["timestamp"])
        XCTAssertNil(properties["latitude"])
        XCTAssertNil(properties["longitude"])
        XCTAssertEqual(trackEvent.timestamp, capturedAt.string(format: .iso8601WithMilliseconds))
    }

    func testSubscribeToJourneyEvents_DataPipelineHandlesTrackGeofenceMetricEvent_pinsSnapshotUserId() async {
        // The transition was captured under user_A; a different user is identified now. The event's
        // snapshot userId must pin the track to user_A, not the current identity.
        customerIO.identify(userId: "user_current")

        await eventBusHandler.postEventAndWait(
            TrackGeofenceMetricEvent(
                geofenceId: String.random,
                transition: .enter,
                timestamp: Date(timeIntervalSince1970: 1700000000),
                name: "HQ",
                transitionId: "txn_pin_1",
                userId: "user_A"
            )
        )

        guard let trackEvent = outputReader.lastEvent as? TrackEvent else {
            XCTFail("recorded event is not an instance of TrackEvent")
            return
        }
        XCTAssertEqual(trackEvent.userId, "user_A")
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

    func testSubscribeToJourneyEvents_givenRegisterDeviceEventWithType_expectTypeInProperties() async {
        let givenToken = String.random

        deviceAttributesMock.getDefaultDeviceAttributesClosure = { $0([:]) }

        await eventBusHandler.postEventAndWait(RegisterDeviceTokenEvent(token: givenToken, tokenType: .fid))

        guard let trackEvent = outputReader.lastEvent as? TrackEvent else {
            XCTFail("recorded event is not an instance of TrackEvent")
            return
        }

        XCTAssertEqual(trackEvent.deviceToken, givenToken)
        XCTAssertEqual(trackEvent.properties?["cio_token_type"]?.stringValue, "fid")
    }

    func testSubscribeToJourneyEvents_givenSameTokenPostedConcurrently_expectDeviceRegisteredOnce() async {
        deviceAttributesMock.getDefaultDeviceAttributesClosure = { $0([:]) }
        // Logged between the stored-token check and the store, so concurrent handlers overlap there
        dataPipelinesLoggerMock.logStoringDevicePushTokenClosure = { _, _ in Thread.sleep(forTimeInterval: 0.02) }

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 10 {
                group.addTask { await self.eventBusHandler.postEventAndWait(RegisterDeviceTokenEvent(token: "token-a")) }
            }
        }

        XCTAssertEqual(deviceEvents(), ["Device Created or Updated token-a"])
    }

    func testSubscribeToJourneyEvents_givenTokenAlreadyStored_expectDeviceNotRegistered() async {
        deviceAttributesMock.getDefaultDeviceAttributesClosure = { $0([:]) }
        globalDataStoreMock.underlyingPushDeviceToken = "token-a"

        await eventBusHandler.postEventAndWait(RegisterDeviceTokenEvent(token: "token-a"))

        XCTAssertEqual(deviceEvents(), [])
    }

    func testSubscribeToJourneyEvents_givenSameTokenPostedWithoutThenWithType_expectTypedOneRegisteredToo() async {
        deviceAttributesMock.getDefaultDeviceAttributesClosure = { $0([:]) }

        await eventBusHandler.postEventAndWait(RegisterDeviceTokenEvent(token: "token-a"))
        await eventBusHandler.postEventAndWait(RegisterDeviceTokenEvent(token: "token-a", tokenType: .fid))

        XCTAssertEqual(deviceEvents(), ["Device Created or Updated token-a", "Device Created or Updated token-a"])
        XCTAssertEqual((outputReader.lastEvent as? TrackEvent)?.properties?["cio_token_type"]?.stringValue, "fid")
    }

    func testSubscribeToJourneyEvents_givenTypeAddedWhileAttributesLoad_expectLastEventHasStoredType() async {
        var pendingAttributes: [([String: Any]) -> Void] = []
        deviceAttributesMock.getDefaultDeviceAttributesClosure = { pendingAttributes.append($0) }

        await eventBusHandler.postEventAndWait(RegisterDeviceTokenEvent(token: "token-a"))
        await eventBusHandler.postEventAndWait(RegisterDeviceTokenEvent(token: "token-a", tokenType: .fid))
        // Attributes can load out of order
        pendingAttributes.reversed().forEach { $0([:]) }

        XCTAssertEqual(typedDeviceEvents().last, "Device Created or Updated token-a fid", "\(typedDeviceEvents())")
    }

    func testSubscribeToJourneyEvents_givenSameTokenPostedWithThenWithoutType_expectDeviceRegisteredOnce() async {
        deviceAttributesMock.getDefaultDeviceAttributesClosure = { $0([:]) }

        await eventBusHandler.postEventAndWait(RegisterDeviceTokenEvent(token: "token-a", tokenType: .fid))
        await eventBusHandler.postEventAndWait(RegisterDeviceTokenEvent(token: "token-a"))

        XCTAssertEqual(deviceEvents(), ["Device Created or Updated token-a"])
    }

    // e.g. the app restored the old token with CustomerIO.shared.registerDeviceToken
    func testSubscribeToJourneyEvents_givenStoredTokenChangesAndChangesBack_expectSameTokenRegisteredAgain() async {
        deviceAttributesMock.getDefaultDeviceAttributesClosure = { $0([:]) }
        customerIO.registerDeviceToken("token-x")

        await eventBusHandler.postEventAndWait(RegisterDeviceTokenEvent(token: "token-a"))
        customerIO.registerDeviceToken("token-x")
        await eventBusHandler.postEventAndWait(RegisterDeviceTokenEvent(token: "token-a"))

        XCTAssertEqual(deviceEvents().filter { $0 == "Device Created or Updated token-a" }.count, 2)
    }

    func testSetDeviceAttributes_givenFidRegisteredBetweenCheckAndTrack_expectEventsKeepTheirOwnTokenAndType() async {
        deviceAttributesMock.getDefaultDeviceAttributesClosure = { $0([:]) }
        await eventBusHandler.postEventAndWait(RegisterDeviceTokenEvent(token: "token-a", tokenType: .token))
        let fidRegistered = expectation(description: "FID registered")
        // Logged between the token check and tracking because a reserved key is passed, so the FID registers there
        dataPipelinesLoggerMock.logReservedDeviceTokenTypeIgnoredClosure = {
            self.dataPipelinesLoggerMock.logReservedDeviceTokenTypeIgnoredClosure = nil
            let registered = DispatchSemaphore(value: 0)
            Task.detached {
                await self.eventBusHandler.postEventAndWait(RegisterDeviceTokenEvent(token: "fid-a", tokenType: .fid))
                registered.signal()
                fidRegistered.fulfill()
            }
            _ = registered.wait(timeout: .now() + 0.2)
        }

        customerIO.setDeviceAttributes(["cio_token_type": "app-value"])
        await fulfillment(of: [fidRegistered], timeout: 2)

        let events = typedDeviceEvents()
        XCTAssertFalse(events.contains("Device Created or Updated fid-a token"), "\(events)")
        // The old token isn't added back after it's deleted
        XCTAssertEqual(events.last, "Device Created or Updated fid-a fid", "\(events)")
    }

    private func typedDeviceEvents() -> [String] {
        outputReader.events.compactMap { $0 as? TrackEvent }
            .filter { $0.event.hasPrefix("Device") }
            .map { "\($0.event) \($0.deviceToken ?? "nil") \($0.properties?["cio_token_type"]?.stringValue ?? "none")" }
    }

    private func deviceEvents() -> [String] {
        outputReader.events.compactMap { $0 as? TrackEvent }
            .filter { $0.event.hasPrefix("Device") }
            .map { "\($0.event) \($0.deviceToken ?? "nil")" }
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
