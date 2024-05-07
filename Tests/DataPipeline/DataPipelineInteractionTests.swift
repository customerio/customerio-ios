@testable import CioAnalytics
@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
@testable import SharedTests
import XCTest

// Base class for testing interactions with the data pipeline.
// The class is meant to be subclassed to run DataPipeline tests with both default and custom configurations.
open class DataPipelineInteractionTests: IntegrationTest {
    fileprivate var outputReader: OutputReaderPlugin!

    fileprivate let deviceAttributesMock = DeviceAttributesProviderMock()
    fileprivate let eventBusHandlerMock = EventBusHandlerMock()
    fileprivate let globalDataStoreMock = GlobalDataStoreMock()

    override open func setUpDependencies() {
        super.setUpDependencies()

        diGraphShared.override(value: deviceAttributesMock, forType: DeviceAttributesProvider.self)
        diGraphShared.override(value: eventBusHandlerMock, forType: EventBusHandler.self)
        diGraphShared.override(value: globalDataStoreMock, forType: GlobalDataStore.self)
    }
}

class CDPInteractionDefaultConfigTests: DataPipelineInteractionTests {
    override open func setUp() {
        super.setUp()

        // OutputReaderPlugin helps validating interactions with analytics
        outputReader = (customerIO.add(plugin: OutputReaderPlugin()) as? OutputReaderPlugin)
    }

    // MARK: identify

    // testing `identify()` with request body. Will make an integration test for all `identify()` functions
    // but copy/paste identify unit tests not needed since only 1 function has logic in it.

    func test_identify_expectSetNewProfileWithoutAttributes() {
        let givenIdentifier = String.random

        XCTAssertNil(analytics.userId)

        customerIO.identify(userId: givenIdentifier)

        XCTAssertEqual(analytics.userId, givenIdentifier)
        XCTAssertNil(analytics.traits())

        XCTAssertEqual(outputReader.identifyEvents.count, 1)
        guard let identifyEvent = outputReader.identifyEvents.last else {
            XCTFail("captured event must not be nil")
            return
        }

        XCTAssertEqual(identifyEvent.userId, givenIdentifier)
        XCTAssertNil(identifyEvent.traits)
    }

    func test_identify_expectSetNewProfileWithAttributes() {
        let givenIdentifier = String.random
        let givenBody: [String: Any] = ["first_name": "Dana", "age": 30]
        let givenBodyTypeMap: [[String]: Any.Type] = [["age"]: Int.self]

        customerIO.identify(userId: givenIdentifier, traits: givenBody)

        XCTAssertEqual(analytics.userId, givenIdentifier)
        XCTAssertMatches(analytics.traits(), givenBody, withTypeMap: givenBodyTypeMap)

        XCTAssertEqual(outputReader.identifyEvents.count, 1)
        guard let identifyEvent = outputReader.identifyEvents.last else {
            XCTFail("captured event must not be nil")
            return
        }

        XCTAssertEqual(identifyEvent.userId, givenIdentifier)
        XCTAssertMatches(identifyEvent.traits?.dictionaryValue, givenBody, withTypeMap: givenBodyTypeMap)
    }

    // MARK: device token

    func test_identify_givenProfileChanged_expectDeleteDeviceTokenForOldProfile() {
        let givenIdentifier = String.random
        let givenPreviouslyIdentifiedProfile = String.random
        let givenDeviceToken = String.random

        globalDataStoreMock.underlyingPushDeviceToken = givenDeviceToken
        mockDeviceAttributes()

        customerIO.identify(userId: givenPreviouslyIdentifiedProfile)
        outputReader.resetPlugin()

        customerIO.identify(userId: givenIdentifier)

        XCTAssertEqual(outputReader.events.count, 3)
        XCTAssertEqual(outputReader.identifyEvents.count, 1)

        let deletedEvents = outputReader.deviceDeleteEvents
        XCTAssertEqual(deletedEvents.count, 1)
        XCTAssertEqual(deletedEvents.first?.deviceToken, givenDeviceToken)

        let updatedEvents = outputReader.deviceUpdateEvents
        XCTAssertEqual(updatedEvents.count, 1)
        XCTAssertEqual(updatedEvents.first?.deviceToken, givenDeviceToken)
    }

    func test_identify_givenProfileReidentified_expectNoDeviceEvents() {
        let givenIdentifier = String.random
        let givenPreviouslyIdentifiedProfile = givenIdentifier
        let givenDeviceToken = String.random

        globalDataStoreMock.underlyingPushDeviceToken = givenDeviceToken
        mockDeviceAttributes()

        customerIO.identify(userId: givenPreviouslyIdentifiedProfile)
        outputReader.resetPlugin()

        customerIO.identify(userId: givenIdentifier)

        XCTAssertEqual(outputReader.events.count, 1)
        XCTAssertEqual(outputReader.identifyEvents.count, 1)
    }

    func test_identify_givenNoProfilePreviouslyIdentified_expectPostProfileEventToEventBus() {
        let givenIdentifier = String.random

        customerIO.identify(userId: givenIdentifier)

        XCTAssertEqual(outputReader.events.count, 1)
        XCTAssertEqual(outputReader.identifyEvents.count, 1)

        XCTAssertEqual(eventBusHandlerMock.postEventCallsCount, 1)
        guard let postEventArgument = eventBusHandlerMock.postEventArguments as? ProfileIdentifiedEvent else {
            XCTFail("captured arguments must not be nil")
            return
        }
        XCTAssertEqual(postEventArgument.identifier, givenIdentifier)
    }

    func test_identify_givenEmptyIdentifier_givenNoProfilePreviouslyIdentified_expectRequestIgnored() {
        let givenIdentifier = ""

        customerIO.identify(userId: givenIdentifier)

        XCTAssertEqual(outputReader.events.count, 0)
        XCTAssertNil(analytics.userId)
    }

    func test_identify_givenEmptyIdentifier_givenProfileAlreadyIdentified_expectRequestIgnored() {
        let givenIdentifier = ""
        let givenPreviouslyIdentifiedProfile = String.random

        customerIO.identify(userId: givenPreviouslyIdentifiedProfile)
        outputReader.resetPlugin()

        customerIO.identify(userId: givenIdentifier)

        XCTAssertEqual(outputReader.events.count, 0)
        XCTAssertEqual(analytics.userId, givenPreviouslyIdentifiedProfile)
    }

    func test_tokenChanged_givenProfileNotIdentified_expectDeleteAndRegisterDeviceToken() {
        let givenPreviousDeviceToken = String.random
        let givenDeviceToken = String.random

        globalDataStoreMock.underlyingPushDeviceToken = givenPreviousDeviceToken
        mockDeviceAttributes()

        customerIO.registerDeviceToken(givenPreviousDeviceToken)
        outputReader.resetPlugin()

        customerIO.registerDeviceToken(givenDeviceToken)

        XCTAssertEqual(outputReader.events.count, 2)

        let deletedEvents = outputReader.deviceDeleteEvents
        XCTAssertEqual(deletedEvents.count, 1)
        XCTAssertEqual(deletedEvents.first?.deviceToken, givenPreviousDeviceToken)

        let updatedEvents = outputReader.deviceUpdateEvents
        XCTAssertEqual(updatedEvents.count, 1)
        XCTAssertEqual(updatedEvents.first?.deviceToken, givenDeviceToken)
    }

    func test_tokenChanged_givenProfileAlreadyIdentified_expectDeleteAndRegisterDeviceToken() {
        let givenIdentifier = String.random
        let givenPreviousDeviceToken = String.random
        let givenDeviceToken = String.random

        mockDeviceAttributes()
        customerIO.identify(userId: givenIdentifier)
        customerIO.registerDeviceToken(givenPreviousDeviceToken)
        outputReader.resetPlugin()

        customerIO.registerDeviceToken(givenDeviceToken)

        XCTAssertEqual(outputReader.events.count, 2)

        let deletedEvents = outputReader.deviceDeleteEvents
        XCTAssertEqual(deletedEvents.count, 1)
        XCTAssertEqual(deletedEvents.first?.deviceToken, givenPreviousDeviceToken)

        let updatedEvents = outputReader.deviceUpdateEvents
        XCTAssertEqual(updatedEvents.count, 1)
        XCTAssertEqual(updatedEvents.first?.deviceToken, givenDeviceToken)
    }

    func test_registerToken_givenProfileIdentifiedBefore_expectRegisterDeviceToken() {
        let givenIdentifier = String.random
        let givenDeviceToken = String.random

        mockDeviceAttributes()
        customerIO.identify(userId: givenIdentifier)
        outputReader.resetPlugin()

        customerIO.registerDeviceToken(givenDeviceToken)

        XCTAssertEqual(outputReader.events.count, 1)

        let updatedEvents = outputReader.deviceUpdateEvents
        XCTAssertEqual(updatedEvents.count, 1)
        XCTAssertEqual(updatedEvents.first?.deviceToken, givenDeviceToken)
    }

    func test_registerToken_givenProfileIdentifiedAfter_expectRegisterDeviceToken() {
        let givenIdentifier = String.random
        let givenDeviceToken = String.random

        mockDeviceAttributes()
        customerIO.registerDeviceToken(givenDeviceToken)
        outputReader.resetPlugin()

        customerIO.identify(userId: givenIdentifier)

        XCTAssertEqual(outputReader.events.count, 2)
        XCTAssertEqual(outputReader.identifyEvents.count, 1)

        let updatedEvents = outputReader.deviceUpdateEvents
        XCTAssertEqual(updatedEvents.count, 1)
        XCTAssertEqual(updatedEvents.first?.deviceToken, givenDeviceToken)
    }

    // MARK: clearIdentify

    func test_clearIdentify_givenPreviouslyIdentifiedProfile_expectUserSetNil() {
        let givenIdentifier = String.random
        customerIO.identify(userId: givenIdentifier)

        customerIO.clearIdentify()

        XCTAssertNil(analytics.userId)
    }

    func test_clearIdentify_expectPostResetEventToEventBus() {
        let givenIdentifier = String.random

        customerIO.identify(userId: givenIdentifier)
        eventBusHandlerMock.resetMock()

        customerIO.clearIdentify()

        XCTAssertEqual(eventBusHandlerMock.postEventCallsCount, 1)
        XCTAssertTrue(eventBusHandlerMock.postEventArguments is ResetEvent)
    }

    // MARK: anonymous user

    // MARK: track events

    func test_event_expectAttributesAttachedCorrectly() {
        let givenIdentifier = String.random
        let givenEvent = String.random

        customerIO.identify(userId: givenIdentifier)
        customerIO.track(name: givenEvent)

        guard let trackEvent = outputReader.lastEvent as? TrackEvent else {
            XCTFail("recorded event is not an instance of TrackEvent")
            return
        }

        XCTAssertEqual(trackEvent.type, "track")
        XCTAssertEqual(trackEvent.userId, givenIdentifier)
        XCTAssertEqual(trackEvent.event, givenEvent)
    }

    // MARK: track

    func test_track_givenAutoTrackDeviceAttributesEnabled_expectSegmentDeviceAttributesInContextNotProperties() {
        let givenDefaultAttributes: [String: Any] = [
            "cio_sdk_version": "3.0.0",
            "push_enabled": true
        ]
        mockDeviceAttributes(defaultAttributes: givenDefaultAttributes)

        customerIO.deviceAttributes = [:]

        customerIO.track(name: String.random)

        XCTAssertEqual(outputReader.events.count, 1)
        XCTAssertEqual(outputReader.trackEvents.count, 1)

        guard let trackEvent = outputReader.lastEvent as? TrackEvent else {
            XCTFail("recorded event is not an instance of TrackEvent")
            return
        }

        let properties = trackEvent.properties?.dictionaryValue
        XCTAssertNil(properties?["network_bluetooth"])
        XCTAssertNil(properties?["network_cellular"])
        XCTAssertNil(properties?["network_wifi"])
        XCTAssertNil(properties?["screen_width"])
        XCTAssertNil(properties?["timezone"])
        XCTAssertNil(properties?["screen_height"])
        XCTAssertNil(properties?["ip"])

        let eventDeviceAttributes = trackEvent.contextDeviceAttributes
        // cio default attributes
        XCTAssertNil(eventDeviceAttributes?["cio_sdk_version"])
        XCTAssertNil(eventDeviceAttributes?["push_enabled"])
        // segment events
        XCTAssertNotNil(eventDeviceAttributes?["id"])
        XCTAssertNotNil(eventDeviceAttributes?["model"])
        XCTAssertNotNil(eventDeviceAttributes?["manufacturer"])
        XCTAssertNotNil(eventDeviceAttributes?["type"])
    }

    func test_track_expectCorrectEventDispatched_expectAssociateEventWithCurrentlyIdentifiedProfile() {
        let givenIdentifier = String.random
        let givenData: [String: Any] = ["first_name": "Dana", "age": 30]

        customerIO.identify(userId: givenIdentifier)
        outputReader.resetPlugin()

        customerIO.track(name: String.random, properties: givenData)

        XCTAssertEqual(outputReader.events.count, 1)
        guard let trackEvent = outputReader.lastEvent as? TrackEvent else {
            XCTFail("recorded event is not an instance of TrackEvent")
            return
        }

        XCTAssertEqual(trackEvent.userId, givenIdentifier)
        XCTAssertMatches(
            trackEvent.properties,
            givenData,
            withTypeMap: [["age"]: Int.self]
        )
    }

    // Tests bug found in: https://github.com/customerio/customerio-ios/issues/134#issuecomment-1028090193
    // If `{"data": null, ...}`, that's a bug that results in HTTP request returning a 400.
    // We want instead: `{"data": {}, ...}`
    func test_track_givenDataNil_expectSaveEmptyRequestData() {
        let givenIdentifier = String.random
        customerIO.identify(userId: givenIdentifier)
        outputReader.resetPlugin()

        let data: EmptyRequestBody? = nil
        customerIO.track(name: String.random, properties: data)

        XCTAssertEqual(outputReader.events.count, 1)
        guard let trackEvent = outputReader.lastEvent as? TrackEvent else {
            XCTFail("recorded event is not an instance of TrackEvent")
            return
        }

        XCTAssertEqual(trackEvent.userId, givenIdentifier)
        XCTAssertNil(trackEvent.properties)
    }

    // MARK: screen

    func test_screen_givenNoProfileIdentified_expectDoNotIgnoreRequest_expectPostGivenEventToEventBus() {
        let givenScreen = String.random

        customerIO.screen(title: givenScreen)

        XCTAssertEqual(outputReader.events.count, 1)

        XCTAssertEqual(eventBusHandlerMock.postEventCallsCount, 1)
        guard let postEventArgument = eventBusHandlerMock.postEventArguments as? ScreenViewedEvent else {
            XCTFail("captured arguments must not be nil")
            return
        }
        XCTAssertEqual(postEventArgument.name, givenScreen)
    }

    func test_screen_expectCorrectEventDispatched_expectCorrectData_expectPostGivenEventToEventBus() {
        let givenIdentifier = String.random
        let givenScreen = String.random
        let givenData: [String: Any] = ["first_name": "Dana", "age": 30]

        customerIO.identify(userId: givenIdentifier)
        outputReader.resetPlugin()
        eventBusHandlerMock.resetMock()

        customerIO.screen(title: givenScreen, properties: givenData)

        XCTAssertEqual(outputReader.events.count, 1)
        guard let screenEvent = outputReader.lastEvent as? ScreenEvent else {
            XCTFail("recorded event is not an instance of ScreenEvent")
            return
        }

        XCTAssertEqual(screenEvent.userId, givenIdentifier)
        XCTAssertMatches(
            screenEvent.properties,
            givenData,
            withTypeMap: [["age"]: Int.self]
        )

        XCTAssertEqual(eventBusHandlerMock.postEventCallsCount, 1)
        guard let postEventArgument = eventBusHandlerMock.postEventArguments as? ScreenViewedEvent else {
            XCTFail("captured arguments must not be nil")
            return
        }
        XCTAssertEqual(postEventArgument.name, givenScreen)
    }

    // MARK: registerDeviceToken

    func test_registerDeviceToken_givenNoProfileIdentified_expectStoreAndRegisterDevice() {
        let givenDeviceToken = String.random
        mockDeviceAttributes()

        customerIO.registerDeviceToken(givenDeviceToken)

        let updatedEvents = outputReader.deviceUpdateEvents
        XCTAssertEqual(updatedEvents.count, 1)

        let deviceUpdatedEvent = updatedEvents.first
        XCTAssertEqual(deviceUpdatedEvent?.deviceToken, givenDeviceToken)
        XCTAssertEqual(globalDataStoreMock.pushDeviceToken, givenDeviceToken)
    }

    func test_registeredDeviceToken_givenDeviceTokenAlreadySaved_expectGivenToken() {
        let givenDeviceToken = String.random
        mockDeviceAttributes()

        customerIO.registerDeviceToken(givenDeviceToken)

        XCTAssertEqual(customerIO.registeredDeviceToken, givenDeviceToken)
    }

    func test_registeredDeviceToken_givenDeviceTokenNotSaved_expectNil() {
        XCTAssertNil(customerIO.registeredDeviceToken)
    }

    func test_registerDeviceToken_givenProfileIdentified_expectStoreAndRegisterDevice() {
        let givenDeviceToken = String.random
        let givenIdentifier = String.random
        let givenDefaultAttributes: [String: Any] = [
            "cio_sdk_version": "3.0.0",
            "push_enabled": true
        ]

        mockDeviceAttributes(defaultAttributes: givenDefaultAttributes)

        customerIO.identify(userId: givenIdentifier)
        outputReader.resetPlugin()

        customerIO.registerDeviceToken(givenDeviceToken)

        let updatedEvents = outputReader.deviceUpdateEvents
        XCTAssertEqual(updatedEvents.count, 1)

        let deviceUpdatedEvent = updatedEvents.first
        XCTAssertEqual(deviceUpdatedEvent?.deviceToken, givenDeviceToken)
        XCTAssertEqual(globalDataStoreMock.pushDeviceToken, givenDeviceToken)

        let actualValues = deviceUpdatedEvent?.properties?.dictionaryValue as? [String: Any]

        // Check for "cio_sdk_version"
        let actualCioSdkVersion = actualValues?["cio_sdk_version"]
        XCTAssertNotNil(actualCioSdkVersion, "Expected 'cio_sdk_version' key is missing")
        if let actualCioSdkVersion = actualCioSdkVersion as? String,
           let expectedCioSdkVersion = givenDefaultAttributes["cio_sdk_version"] as? String {
            XCTAssertEqual(actualCioSdkVersion, expectedCioSdkVersion, "'cio_sdk_version' does not match")
        }

        // Check for "push_enabled"
        let actualPushEnabled = actualValues?["push_enabled"]
        XCTAssertNotNil(actualPushEnabled, "Expected 'push_enabled' key is missing")
        if let actualPushEnabled = actualPushEnabled as? Bool,
           let expectedPushEnabled = givenDefaultAttributes["push_enabled"] as? Bool {
            XCTAssertEqual(actualPushEnabled, expectedPushEnabled, "'push_enabled' does not match")
        }
    }

    func test_registerDeviceToken_givenNoOsNameAvailable_expectDeviceCreateEvent() {
        let givenDeviceToken = String.random
        globalDataStoreMock.pushDeviceToken = givenDeviceToken

        deviceInfoStub.osName = nil
        mockDeviceAttributes()

        customerIO.identify(userId: String.random)
        outputReader.resetPlugin()

        customerIO.registerDeviceToken(givenDeviceToken)

        let deviceUpdatedEvent = outputReader.deviceUpdateEvents
        XCTAssertEqual(deviceUpdatedEvent.count, 1)
        XCTAssertEqual(globalDataStoreMock.pushDeviceToken, givenDeviceToken)
    }

    // MARK: deleteDeviceToken

    func test_deleteDeviceToken_givenNoProfileIdentified_givenNoExistingPushToken_expectNoEventDispatched() {
        globalDataStoreMock.pushDeviceToken = nil
        customerIO.clearIdentify()
        outputReader.resetPlugin()

        customerIO.deleteDeviceToken()

        XCTAssertEqual(outputReader.events.count, 0)
        XCTAssertNil(globalDataStoreMock.pushDeviceToken)
    }

    func test_deleteDeviceToken_givenProfileIdentified_givenNoExistingPushToken_expectNoEventDispatched() {
        globalDataStoreMock.pushDeviceToken = nil
        let givenIdentifier = String.random

        customerIO.identify(userId: givenIdentifier)
        outputReader.resetPlugin()

        customerIO.deleteDeviceToken()

        XCTAssertEqual(outputReader.events.count, 0)
        XCTAssertNil(globalDataStoreMock.pushDeviceToken)
    }

    func test_deleteDeviceToken_givenNoProfileIdentified_givenExistingPushToken_expectNoEventDispatched() {
        globalDataStoreMock.pushDeviceToken = String.random
        customerIO.clearIdentify()
        outputReader.resetPlugin()

        customerIO.deleteDeviceToken()

        XCTAssertEqual(outputReader.deviceDeleteEvents.count, 1)
        XCTAssertNotNil(globalDataStoreMock.pushDeviceToken)
    }

    func test_deleteDeviceToken_givenProfileIdentified_givenExistingPushToken_expectDeleteDeviceEvent() {
        let givenDeviceToken = String.random
        let givenIdentifier = String.random

        globalDataStoreMock.pushDeviceToken = givenDeviceToken
        customerIO.identify(userId: givenIdentifier)
        outputReader.resetPlugin()

        customerIO.deleteDeviceToken()

        let deviceDeletedEvents = outputReader.deviceDeleteEvents
        XCTAssertEqual(deviceDeletedEvents.count, 1)

        let deviceDeletedEventToken = deviceDeletedEvents.first?.deviceToken
        XCTAssertEqual(deviceDeletedEventToken, givenDeviceToken)

        XCTAssertEqual(analytics.userId, givenIdentifier)
        XCTAssertEqual(globalDataStoreMock.pushDeviceToken, givenDeviceToken)
    }

    // MARK: trackMetric

    func test_trackMetric_expectCorrectEventDispatched() {
        let givenDeliveryId = String.random
        let givenEvent = Metric.delivered
        let givenDeviceToken = String.random

        customerIO.identify(userId: String.random)
        outputReader.resetPlugin()

        customerIO.trackMetric(deliveryID: givenDeliveryId, event: givenEvent, deviceToken: givenDeviceToken)

        XCTAssertEqual(outputReader.events.count, 1)
        guard let metricEvent = outputReader.lastEvent as? TrackEvent else {
            XCTFail("recorded event is not an instance of TrackEvent")
            return
        }
        XCTAssertEqual(metricEvent.event, "Report Delivery Event")

        let properties = metricEvent.properties
        XCTAssertEqual(properties?.value(forKeyPath: KeyPath("deliveryId")), givenDeliveryId)
        XCTAssertEqual(properties?.value(forKeyPath: KeyPath("metric")), givenEvent.rawValue)
        XCTAssertEqual(properties?.value(forKeyPath: KeyPath("recipient")), givenDeviceToken)
    }
}

class CDPInteractionCustomConfigTests: DataPipelineInteractionTests {
    override func setUp() {
        // keep setUp empty to prevent default setUp so we can test with custom configurations for each test.
    }

    override func setUp(enableLogs: Bool = false, cdpApiKey: String? = nil, modifySdkConfig: ((SDKConfigBuilder) -> Void)?) {
        super.setUp(enableLogs: enableLogs, cdpApiKey: cdpApiKey, modifySdkConfig: modifySdkConfig)
        // OutputReaderPlugin helps validating interactions with analytics
        outputReader = (customerIO.add(plugin: OutputReaderPlugin()) as? OutputReaderPlugin)
    }

    func test_track_givenAutoTrackDeviceAttributesDisabled_expectNoDeviceAttributesInProperties() {
        setUp(modifySdkConfig: { config in
            config.autoTrackDeviceAttributes(false)
        })

        let givenIdentifier = String.random
        let givenDeviceToken = String.random

        mockDeviceAttributes()
        customerIO.identify(userId: givenIdentifier)
        outputReader.resetPlugin()

        customerIO.registerDeviceToken(givenDeviceToken)

        guard let trackEvent = outputReader.deviceUpdateEvents.last else {
            XCTFail("recorded event is not an instance of TrackEvent")
            return
        }

        let eventDeviceAttributes = trackEvent.properties
        // cio default attributes
        XCTAssertNil(eventDeviceAttributes?["cio_sdk_version"])
        XCTAssertNil(eventDeviceAttributes?["push_enabled"])
        // segment events
        XCTAssertNil(eventDeviceAttributes?["id"])
        XCTAssertNil(eventDeviceAttributes?["model"])
        XCTAssertNil(eventDeviceAttributes?["manufacturer"])
        XCTAssertNil(eventDeviceAttributes?["type"])
    }
}

extension DataPipelineInteractionTests {
    func mockDeviceAttributes(defaultAttributes: [String: Any] = [:]) {
        deviceAttributesMock.getDefaultDeviceAttributesClosure = { $0(defaultAttributes) }
    }
}
