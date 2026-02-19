@testable import CioAnalytics
@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
@testable import SharedTests
import XCTest

class DataPipelineLocationGuardrailsTests: IntegrationTest {
    private var outputReader: OutputReaderPlugin!
    private var eventBusHandler: EventBusHandler { diGraphShared.eventBusHandler }

    override func setUp() {
        super.setUp(modifySdkConfig: nil)
        outputReader = (customerIO.add(plugin: OutputReaderPlugin()) as? OutputReaderPlugin)
    }

    // MARK: - Reserved track event name

    func testTrack_whenReservedLocationEventName_ignoresCall() {
        customerIO.identify(userId: String.random)
        outputReader.resetPlugin()

        customerIO.track(name: DataPipelineReservedNames.reservedLocationTrackEventName, properties: ["lat": 1.0, "lng": 2.0])

        XCTAssertEqual(outputReader.events.count, 0, "Reserved event name should not produce a track event")
    }

    func testTrack_whenReservedEventName_thenOtherEvent_stillSendsOtherEvent() {
        customerIO.identify(userId: String.random)
        outputReader.resetPlugin()

        customerIO.track(name: DataPipelineReservedNames.reservedLocationTrackEventName, properties: nil)
        customerIO.track(name: "Other Event", properties: ["key": "value"])

        XCTAssertEqual(outputReader.trackEvents.count, 1)
        guard let trackEvent = outputReader.lastEvent as? TrackEvent else {
            XCTFail("Expected one TrackEvent")
            return
        }
        XCTAssertEqual(trackEvent.event, "Other Event")
        XCTAssertEqual(trackEvent.properties?.dictionaryValue?["key"] as? String, "value")
    }

    // MARK: - Filter location attributes from track properties

    func testTrack_whenPropertiesContainReservedLocationKeys_stripsThemAndSendsRest() {
        customerIO.identify(userId: String.random)
        outputReader.resetPlugin()

        let properties: [String: Any] = [
            "location_latitude": 37.7,
            "location_longitude": -122.4,
            "other": "kept"
        ]
        customerIO.track(name: "Custom Event", properties: properties)

        guard let trackEvent = outputReader.lastEvent as? TrackEvent else {
            XCTFail("Expected TrackEvent")
            return
        }
        let sent = trackEvent.properties?.dictionaryValue
        XCTAssertNil(sent?["location_latitude"])
        XCTAssertNil(sent?["location_longitude"])
        XCTAssertEqual(sent?["other"] as? String, "kept")
    }

    func testTrack_whenOnlyReservedLocationKeys_sendsEventWithNoProperties() {
        customerIO.identify(userId: String.random)
        outputReader.resetPlugin()

        customerIO.track(name: "Custom Event", properties: [
            "location_latitude": 37.7,
            "location_longitude": -122.4
        ])

        guard let trackEvent = outputReader.lastEvent as? TrackEvent else {
            XCTFail("Expected TrackEvent")
            return
        }
        XCTAssertEqual(trackEvent.event, "Custom Event")
        XCTAssertTrue(trackEvent.properties?.dictionaryValue?.isEmpty ?? true)
    }

    // MARK: - Filter location attributes from profile (identify / setProfileAttributes)

    func testSetProfileAttributes_whenContainsReservedLocationKeys_stripsThemAndSendsRest() {
        customerIO.identify(userId: String.random)
        outputReader.resetPlugin()

        customerIO.setProfileAttributes([
            "location_latitude": 40.0,
            "location_longitude": -74.0,
            "email": "test@example.com"
        ])

        let identifyEvents = outputReader.identifyEvents
        XCTAssertEqual(identifyEvents.count, 1)
        let traits = identifyEvents[0].traits?.dictionaryValue
        XCTAssertNil(traits?["location_latitude"])
        XCTAssertNil(traits?["location_longitude"])
        XCTAssertEqual(traits?["email"] as? String, "test@example.com")
    }

    func testIdentifyWithTraits_whenContainsReservedLocationKeys_stripsThemAndSendsRest() {
        outputReader.resetPlugin()

        customerIO.identify(userId: String.random, traits: [
            "location_latitude": 40.0,
            "location_longitude": -74.0,
            "name": "Jane"
        ])

        let identifyEvents = outputReader.identifyEvents
        XCTAssertEqual(identifyEvents.count, 1)
        let traits = identifyEvents[0].traits?.dictionaryValue
        XCTAssertNil(traits?["location_latitude"])
        XCTAssertNil(traits?["location_longitude"])
        XCTAssertEqual(traits?["name"] as? String, "Jane")
    }

    func testSetProfileAttributes_whenOnlyOtherAttributes_stillSendsUpdate() {
        customerIO.identify(userId: String.random)
        outputReader.resetPlugin()

        customerIO.setProfileAttributes(["email": "user@test.com"])

        let identifyEvents = outputReader.identifyEvents
        XCTAssertEqual(identifyEvents.count, 1)
        XCTAssertEqual(identifyEvents[0].traits?.dictionaryValue?["email"] as? String, "user@test.com")
    }

    // MARK: - Internal location flow still works

    func testTrackLocationEvent_stillTracksLocationUpdate() async {
        customerIO.identify(userId: String.random)
        outputReader.resetPlugin()

        let givenLocationData = LocationData(latitude: 37.7749, longitude: -122.4194)
        await eventBusHandler.postEventAndWait(TrackLocationEvent(location: givenLocationData))

        guard let trackEvent = outputReader.lastEvent as? TrackEvent else {
            XCTFail("Expected TrackEvent from TrackLocationEvent")
            return
        }
        XCTAssertEqual(trackEvent.event, DataPipelineReservedNames.reservedLocationTrackEventName)
        let properties = trackEvent.properties?.dictionaryValue
        XCTAssertEqual(properties?["lat"] as? Double, 37.7749)
        XCTAssertEqual(properties?["lng"] as? Double, -122.4194)
    }
}
