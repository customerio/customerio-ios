@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
@testable import Segment
import SharedTests
import XCTest

class DataPipelineInteractionTests: UnitTest {
    // When calling CustomerIOInstance functions in the test functions, use this `CustomerIO` instance.
    // This is a workaround until this code base contains implementation tests. There have been bugs
    // that have gone undiscovered in the code when `CustomerIO` passes a request to `DataPipelineImplementation`.
    private var customerIO: CustomerIO!
    private var analytics: Analytics!
    private var outputReader: OutputReaderPlugin!

    private let deviceAttributesMock = DeviceAttributesProviderMock()
    private let deviceInfoMock = DeviceInfoMock()
    private let eventBusHandlerMock = EventBusHandlerMock()
    private let globalDataStoreMock = GlobalDataStoreMock()

    override func setUp() {
        super.setUp()

        diGraphShared.override(value: dateUtilStub, forType: DateUtil.self)
        diGraphShared.override(value: deviceAttributesMock, forType: DeviceAttributesProvider.self)
        diGraphShared.override(value: deviceInfoMock, forType: DeviceInfo.self)
        diGraphShared.override(value: eventBusHandlerMock, forType: EventBusHandler.self)
        diGraphShared.override(value: globalDataStoreMock, forType: GlobalDataStore.self)

        let moduleConfig = DataPipelineConfigOptions.Factory.create(writeKey: "test")
        let implementation = DataPipelineImplementation(diGraph: diGraphShared, moduleConfig: moduleConfig)

        DataPipeline.setupSharedTestInstance(implementation: implementation, config: moduleConfig)
        customerIO = CustomerIO(implementation: implementation, diGraph: diGraph)

        // setting up analytics for testing
        analytics = implementation.analytics
        // OutputReaderPlugin helps validating interactions with analytics
        outputReader = OutputReaderPlugin()
        analytics.add(plugin: outputReader)
        // wait for analytics queue to start emitting events
        waitUntilStarted(analytics: analytics)
    }

    override func tearDown() {
        customerIO.clearIdentify()
        super.tearDown()
    }

    // MARK: identify

    // testing `identify()` with request body. Will make an integration test for all `identify()` functions
    // but copy/paste identify unit tests not needed since only 1 function has logic in it.

    func test_identify_expectSetNewProfileWithoutAttributes() {
        let givenIdentifier = String.random

        XCTAssertNil(analytics.userId)

        customerIO.identify(identifier: givenIdentifier)

        XCTAssertEqual(analytics.userId, givenIdentifier)
        XCTAssertEqual(analytics.traits()?.count, 0)

        XCTAssertEqual(filterIdentify(outputReader.events).count, 1)

        let identifyEvent = filterIdentify(outputReader.events).first
        XCTAssertEqual(identifyEvent?.userId, givenIdentifier)
        XCTAssertEqual(identifyEvent?.traits?.dictionaryValue?.count, 0)
    }

    func test_identify_expectSetNewProfileWithAttributes() {
        let givenIdentifier = String.random
        let givenBody: [String: Any] = ["first_name": "Dana", "age": 30]

        customerIO.identify(identifier: givenIdentifier, body: givenBody)

        let traitsComparer: (_ key: String, _ expected: [String: Any], _ actual: [String: Any]) -> Void = { key, expected, actual in
            switch key {
            case "first_name":
                XCTAssertEqual((expected[key] as! String), actual[key] as? String)
            case "age":
                XCTAssertEqual((expected[key] as! Int), actual[key] as? Int)
            default:
                XCTFail("unexpected key received: '\(key)'")
            }
        }

        XCTAssertEqual(analytics.userId, givenIdentifier)
        assertDictionariesEqual(givenBody, analytics.traits(), compare: traitsComparer)

        let identifyEvent = filterIdentify(outputReader.events).first
        XCTAssertEqual(identifyEvent?.userId, givenIdentifier)
        assertDictionariesEqual(givenBody, identifyEvent?.traits?.dictionaryValue, compare: traitsComparer)
    }

    // MARK: device token

    func test_identify_givenProfileChanged_expectDeleteDeviceTokenForOldProfile() {
        let givenIdentifier = String.random
        let givenPreviouslyIdentifiedProfile = String.random
        let givenDeviceToken = String.random

        mockDeviceTokenDependencies(token: givenDeviceToken)
        customerIO.identify(identifier: givenPreviouslyIdentifiedProfile)
        outputReader.resetPlugin()

        customerIO.identify(identifier: givenIdentifier)

        XCTAssertEqual(outputReader.events.count, 3)
        XCTAssertEqual(filterIdentify(outputReader.events).count, 1)

        let deletedEvents = filterDeviceDeleted(outputReader.events)
        XCTAssertEqual(deletedEvents.count, 1)
        XCTAssertEqual(getDeviceToken(deletedEvents.first), givenDeviceToken)

        let createdEvents = filterDeviceCreated(outputReader.events)
        XCTAssertEqual(createdEvents.count, 1)
        XCTAssertEqual(getDeviceToken(createdEvents.first), givenDeviceToken)
    }

    func test_identify_givenProfileReidentified_expectNoDeviceEvents() {
        let givenIdentifier = String.random
        let givenPreviouslyIdentifiedProfile = givenIdentifier
        let givenDeviceToken = String.random

        mockDeviceTokenDependencies(token: givenDeviceToken)
        customerIO.identify(identifier: givenPreviouslyIdentifiedProfile)
        outputReader.resetPlugin()

        customerIO.identify(identifier: givenIdentifier)

        XCTAssertEqual(outputReader.events.count, 1)
        XCTAssertEqual(filterIdentify(outputReader.events).count, 1)
    }

    func test_identify_givenProfileNotIdentified_expectNoDeviceEvents() {
        let givenDeviceToken = String.random
        mockDeviceTokenDependencies(token: givenDeviceToken)

        customerIO.registerDeviceToken(givenDeviceToken)

        XCTAssertEqual(outputReader.events.count, 0)
    }

    func test_identify_givenEmptyIdentifier_givenNoProfilePreviouslyIdentified_expectRequestIgnored() {
        let givenIdentifier = ""

        customerIO.identify(identifier: givenIdentifier)

        XCTAssertEqual(outputReader.events.count, 0)
        XCTAssertNil(analytics.userId)
    }

    func test_identify_givenEmptyIdentifier_givenProfileAlreadyIdentified_expectRequestIgnored() {
        let givenIdentifier = ""
        let givenPreviouslyIdentifiedProfile = String.random

        customerIO.identify(identifier: givenPreviouslyIdentifiedProfile)
        outputReader.resetPlugin()

        customerIO.identify(identifier: givenIdentifier)

        XCTAssertEqual(outputReader.events.count, 0)
        XCTAssertEqual(analytics.userId, givenPreviouslyIdentifiedProfile)
    }

    func test_tokenChanged_givenProfileNotIdentified_expectNoDeviceEvent() {
        let givenPreviousDeviceToken = String.random
        let givenDeviceToken = String.random

        mockDeviceTokenDependencies(token: givenPreviousDeviceToken)
        outputReader.resetPlugin()

        customerIO.registerDeviceToken(givenDeviceToken)

        XCTAssertEqual(outputReader.events.count, 0)
    }

    func test_tokenChanged_givenProfileAlreadyIdentified_expectDeleteAndRegisterDeviceToken() {
        let givenIdentifier = String.random
        let givenPreviousDeviceToken = String.random
        let givenDeviceToken = String.random

        mockDeviceTokenDependencies()
        customerIO.identify(identifier: givenIdentifier)
        customerIO.registerDeviceToken(givenPreviousDeviceToken)
        outputReader.resetPlugin()

        customerIO.registerDeviceToken(givenDeviceToken)

        XCTAssertEqual(outputReader.events.count, 2)

        let deletedEvents = filterDeviceDeleted(outputReader.events)
        XCTAssertEqual(deletedEvents.count, 1)
        XCTAssertEqual(getDeviceToken(deletedEvents.first), givenPreviousDeviceToken)

        let createdEvents = filterDeviceCreated(outputReader.events)
        XCTAssertEqual(createdEvents.count, 1)
        XCTAssertEqual(getDeviceToken(createdEvents.first), givenDeviceToken)
    }

    func test_registerToken_givenProfileIdentifiedBefore_expectRegisterDeviceToken() {
        let givenIdentifier = String.random
        let givenDeviceToken = String.random

        mockDeviceTokenDependencies()
        customerIO.identify(identifier: givenIdentifier)
        outputReader.resetPlugin()

        customerIO.registerDeviceToken(givenDeviceToken)

        XCTAssertEqual(outputReader.events.count, 1)

        let createdEvents = filterDeviceCreated(outputReader.events)
        XCTAssertEqual(createdEvents.count, 1)
        XCTAssertEqual(getDeviceToken(createdEvents.first), givenDeviceToken)
    }

    func test_registerToken_givenProfileIdentifiedAfter_expectRegisterDeviceToken() {
        let givenIdentifier = String.random
        let givenDeviceToken = String.random

        mockDeviceTokenDependencies()
        customerIO.registerDeviceToken(givenDeviceToken)
        outputReader.resetPlugin()

        customerIO.identify(identifier: givenIdentifier)

        XCTAssertEqual(outputReader.events.count, 2)
        XCTAssertEqual(filterIdentify(outputReader.events).count, 1)

        let createdEvents = filterDeviceCreated(outputReader.events)
        XCTAssertEqual(createdEvents.count, 1)
        XCTAssertEqual(getDeviceToken(createdEvents.first), givenDeviceToken)
    }

    // MARK: clearIdentify

    func test_clearIdentify_givenPreviouslyIdentifiedProfile_expectUserSetNil() {
        let givenIdentifier = String.random
        customerIO.identify(identifier: givenIdentifier)

        customerIO.clearIdentify()

        XCTAssertNil(analytics.userId)
    }

    func test_clearIdentify_expectAbleToGetIdentifierFromStorageInHooks() {
        XCTSkip("Needs to be fixed")
//        let givenIdentifier = String.random
//        profileStoreMock.identifier = givenIdentifier
//        let expect = expectation(description: "Expect to call hook")
//        profileIdentifyHookMock.beforeProfileStoppedBeingIdentifiedClosure = { actualOldIdentifier in
//            XCTAssertNotNil(self.profileStoreMock.identifier)
//            XCTAssertEqual(self.profileStoreMock.identifier, actualOldIdentifier)
//
//            expect.fulfill()
//        }
//
//        customerIO.clearIdentify()
//
//        waitForExpectations()
//
//        XCTAssertNil(profileStoreMock.identifier)
    }

    // MARK: anonymous user

    // MARK: track events

    func test_event_expectAttributesAttachedCorrectly() {
        let givenIdentifier = String.random
        let givenEvent = String.random

        customerIO.identify(identifier: givenIdentifier)
        customerIO.track(name: givenEvent)

        guard let trackEvent = outputReader.lastEvent as? TrackEvent else {
            XCTFail("Recorded event is not an instance of TrackEvent")
            return
        }

        XCTAssertEqual(trackEvent.type, "track")
        XCTAssertEqual(trackEvent.userId, givenIdentifier)
        XCTAssertEqual(trackEvent.event, givenEvent)
    }

    // MARK: track

    func test_track_expectAddTaskToQueue_expectAssociateEventWithCurrentlyIdentifiedProfile() {
        let givenIdentifier = String.random
        let givenData: [String: Any] = ["first_name": "Dana", "age": 30]

        customerIO.identify(identifier: givenIdentifier)
        outputReader.resetPlugin()

        customerIO.track(name: String.random, data: givenData)

        let events = outputReader.events
        XCTAssertEqual(events.count, 1)

        let event = outputReader.lastEvent
        XCTAssertTrue(event is TrackEvent)
        XCTAssertEqual(event?.userId, givenIdentifier)

        assertDictionariesEqual(givenData, getProperties(event)) { key, expected, actual in
            switch key {
            case "first_name":
                XCTAssertEqual((expected[key] as! String), actual[key] as? String)
            case "age":
                XCTAssertEqual((expected[key] as! Int), actual[key] as? Int)
            default:
                XCTFail("unexpected key received: '\(key)'")
            }
        }
    }

    // Tests bug found in: https://github.com/customerio/customerio-ios/issues/134#issuecomment-1028090193
    // If `{"data": null, ...}`, that's a bug that results in HTTP request returning a 400.
    // We want instead: `{"data": {}, ...}`
    func test_track_givenDataNil_expectSaveEmptyRequestData() {
        let givenIdentifier = String.random
        customerIO.identify(identifier: givenIdentifier)
        outputReader.resetPlugin()

        let data: EmptyRequestBody? = nil
        customerIO.track(name: String.random, data: data)

        let events = outputReader.events
        XCTAssertEqual(events.count, 1)

        let event = outputReader.lastEvent
        XCTAssertTrue(event is TrackEvent)
        XCTAssertEqual(event?.userId, givenIdentifier)

        let properties = getProperties(event)
        XCTAssertNil(properties)
    }

    // MARK: screen

    func test_screen_givenNoProfileIdentified_expectDoNotIgnoreRequest_expectCallEventBus() {
        let givenScreen = String.random

        customerIO.screen(name: givenScreen)

        XCTAssertEqual(outputReader.events.count, 1)

        XCTAssertEqual(eventBusHandlerMock.postEventCallsCount, 1)
        let postEventArgument = eventBusHandlerMock.postEventArguments as? ScreenViewedEvent
        XCTAssertNotNil(postEventArgument)
        XCTAssertEqual(postEventArgument?.name, givenScreen)
    }

    func test_screen_expectAddTaskToQueue_expectCorrectDataAddedToQueue_expectCallHooks() {
        let givenIdentifier = String.random
        let givenScreen = String.random
        let givenData: [String: Any] = ["first_name": "Dana", "age": 30]

        customerIO.identify(identifier: givenIdentifier)
        outputReader.resetPlugin()
        eventBusHandlerMock.resetMock()

        customerIO.screen(name: givenScreen, data: givenData)

        let events = outputReader.events
        XCTAssertEqual(events.count, 1)

        let event = outputReader.lastEvent
        XCTAssertTrue(event is ScreenEvent)
        XCTAssertEqual(event?.userId, givenIdentifier)

        assertDictionariesEqual(givenData, getProperties(event)) { key, expected, actual in
            switch key {
            case "first_name":
                XCTAssertEqual((expected[key] as! String), actual[key] as? String)
            case "age":
                XCTAssertEqual((expected[key] as! Int), actual[key] as? Int)
            default:
                XCTFail("unexpected key received: '\(key)'")
            }
        }

        XCTAssertEqual(eventBusHandlerMock.postEventCallsCount, 1)
        let postEventArgument = eventBusHandlerMock.postEventArguments as? ScreenViewedEvent
        XCTAssertNotNil(postEventArgument)
        XCTAssertEqual(postEventArgument?.name, givenScreen)
    }

    // MARK: registerDeviceToken

    // TODO: [CDP] Confirm if this is still desired behavior
    func test_registerDeviceToken_givenNoProfileIdentified_expectNoDeviceEvent() {
        let givenDeviceToken = String.random
        mockDeviceTokenDependencies()

        customerIO.registerDeviceToken(givenDeviceToken)

        XCTAssertEqual(outputReader.events.count, 0)
        XCTAssertEqual(globalDataStoreMock.pushDeviceToken, givenDeviceToken)
    }

    func test_registeredDeviceToken_givenDeviceTokenAlreadySaved_expectGivenToken() {
        let givenDeviceToken = String.random
        mockDeviceTokenDependencies()

        customerIO.registerDeviceToken(givenDeviceToken)

        XCTAssertEqual(customerIO.registeredDeviceToken, givenDeviceToken)
    }

    func test_registeredDeviceToken_givenDeviceTokenNotSaved_expectNil() {
        XCTAssertNil(customerIO.registeredDeviceToken)
    }

    func test_registerDeviceToken_givenProfileIdentified_expectStoreAndRegisterDevice() {
        let givenDeviceToken = String.random
        let givenIdentifier = String.random
        let givenDefaultAttributes: [String: Any] = ["foo": "bar"]
        let expectedAttributes = givenDefaultAttributes.mergeWith([
            "last_used": dateUtilStub.givenNow
        ])

        mockDeviceTokenDependencies(defaultAttributes: givenDefaultAttributes)
        customerIO.identify(identifier: givenIdentifier)
        outputReader.resetPlugin()

        customerIO.registerDeviceToken(givenDeviceToken)

        let deviceCreatedEvents = filterDeviceCreated(outputReader.events)
        XCTAssertEqual(deviceCreatedEvents.count, 1)

        let deviceCreatedEvent = outputReader.lastEvent
        XCTAssertEqual(getDeviceToken(deviceCreatedEvent), givenDeviceToken)
        XCTAssertEqual(globalDataStoreMock.pushDeviceToken, givenDeviceToken)

        assertDictionariesEqual(expectedAttributes, getProperties(deviceCreatedEvent)) { key, expected, actual in
            switch key {
            case "foo":
                XCTAssertEqual((expected[key] as! String), actual[key] as? String)
            case "last_used":
                    // analytics SDK wraps date in double quotes
                let actualValue = ((actual[key] as? Encodable)?.toString())?.trimmingCharacters(in: CharacterSet.punctuationCharacters)
                XCTAssertEqual((expected[key] as! Date).iso8601(), actualValue)
            default:
                XCTFail("unexpected key received: '\(key)'")
            }
        }
    }

    func test_registerDeviceToken_givenNoOsNameAvailable_expectNoAddingToQueue() {
        let givenDeviceToken = String.random
        globalDataStoreMock.pushDeviceToken = givenDeviceToken

        mockDeviceTokenDependencies(underlyingOsName: nil)
        customerIO.identify(identifier: String.random)
        outputReader.resetPlugin()

        customerIO.registerDeviceToken(givenDeviceToken)

        let deviceCreatedEvents = filterDeviceCreated(outputReader.events)
        XCTAssertEqual(deviceCreatedEvents.count, 1)
        XCTAssertEqual(globalDataStoreMock.pushDeviceToken, givenDeviceToken)
    }

    // MARK: deleteDeviceToken

    func test_deleteDeviceToken_givenNoProfileIdentified_givenNoExistingPushToken_expectNoAddingTaskToQueue() {
        globalDataStoreMock.pushDeviceToken = nil
        customerIO.clearIdentify()
        outputReader.resetPlugin()

        customerIO.deleteDeviceToken()

        let events = outputReader.events
        XCTAssertEqual(events.count, 0)
        XCTAssertNil(globalDataStoreMock.pushDeviceToken)
    }

    func test_deleteDeviceToken_givenProfileIdentified_givenNoExistingPushToken_expectNoAddingTaskToQueue() {
        globalDataStoreMock.pushDeviceToken = nil
        let givenIdentifier = String.random

        customerIO.identify(identifier: givenIdentifier)
        outputReader.resetPlugin()

        customerIO.deleteDeviceToken()

        let events = outputReader.events
        XCTAssertEqual(events.count, 0)
        XCTAssertNil(globalDataStoreMock.pushDeviceToken)
    }

    func test_deleteDeviceToken_givenNoProfileIdentified_givenExistingPushToken_expectNoAddingTaskToQueue() {
        globalDataStoreMock.pushDeviceToken = String.random
        customerIO.clearIdentify()
        outputReader.resetPlugin()

        customerIO.deleteDeviceToken()

        let deviceDeletedEvents = filterDeviceDeleted(outputReader.events)
        XCTAssertEqual(deviceDeletedEvents.count, 1)
        XCTAssertNotNil(globalDataStoreMock.pushDeviceToken)
    }

    func test_deleteDeviceToken_givenProfileIdentified_givenExistingPushToken_expectAddTaskToQueue() {
        let givenDeviceToken = String.random
        let givenIdentifier = String.random

        globalDataStoreMock.pushDeviceToken = givenDeviceToken
        customerIO.identify(identifier: givenIdentifier)
        outputReader.resetPlugin()

        customerIO.deleteDeviceToken()

        let deviceDeletedEvents = filterDeviceDeleted(outputReader.events)
        let deviceDeletedEvent = getDeviceToken(outputReader.lastEvent)
        XCTAssertEqual(deviceDeletedEvents.count, 1)
        XCTAssertEqual(deviceDeletedEvent, givenDeviceToken)

        XCTAssertEqual(analytics.userId, givenIdentifier)
        XCTAssertEqual(globalDataStoreMock.pushDeviceToken, givenDeviceToken)
    }

    // MARK: trackMetric

    func test_trackMetric_expectAddTaskToQueue() {
        let givenDeliveryId = String.random
        let givenEvent = Metric.delivered
        let givenDeviceToken = String.random

        customerIO.identify(identifier: String.random)
        outputReader.resetPlugin()

        customerIO.trackMetric(deliveryID: givenDeliveryId, event: givenEvent, deviceToken: givenDeviceToken)

        XCTAssertEqual(outputReader.events.count, 1)

        guard let metricEvent = outputReader.lastEvent as? TrackEvent else {
            XCTFail("Recorded event is not an instance of TrackEvent")
            return
        }
        XCTAssertEqual(metricEvent.event, "Report Delivery Event")

        let properties = metricEvent.properties
        XCTAssertEqual(properties?.value(forKeyPath: KeyPath("deliveryId")), givenDeliveryId)
        XCTAssertEqual(properties?.value(forKeyPath: KeyPath("metric")), givenEvent.rawValue)
        XCTAssertEqual(properties?.value(forKeyPath: KeyPath("recipient")), givenDeviceToken)
    }
}

extension DataPipelineInteractionTests {
    private func mockDeviceTokenDependencies(
        token: String? = nil,
        underlyingOsName: String? = "iOS",
        defaultAttributes: [String: Any] = [:]
    ) {
        globalDataStoreMock.underlyingPushDeviceToken = token

        deviceInfoMock.underlyingOsName = underlyingOsName
        deviceInfoMock.underlyingSdkVersion = "3.0.0"
        deviceInfoMock.underlyingCustomerAppVersion = "1.2.3"
        deviceInfoMock.underlyingDeviceLocale = String.random
        deviceInfoMock.underlyingDeviceManufacturer = String.random
        deviceInfoMock.isPushSubscribedClosure = { $0(true) }

        deviceAttributesMock.getDefaultDeviceAttributesClosure = { $0(defaultAttributes) }
    }

    func assertDictionariesEqual(
        _ expected: [String: Any],
        _ actual: [String: Any]?,
        compare: (_ key: String, _ expected: [String: Any], _ actual: [String: Any]) -> Void,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard let actual = actual else {
            XCTFail("actual dictionary is nil", file: file, line: line)
            return
        }

        guard expected.keys == actual.keys else {
            XCTFail("actual dictionary has different keys from expected value", file: file, line: line)
            return
        }

        for key in expected.keys {
            compare(key, expected, actual)
        }
    }

    func getDeviceToken(_ event: RawEvent?) -> String? {
        if let context = event?.context?.dictionaryValue {
            return context[keyPath: "device.token"] as? String
        }
        return nil
    }

    func getProperties(_ event: RawEvent?) -> [String: Any]? {
        if let event = event as? TrackEvent {
            return event.properties?.dictionaryValue
        } else if let event = event as? ScreenEvent {
            return event.properties?.dictionaryValue
        }
        return nil
    }

    func filterIdentify(_ events: [RawEvent]) -> [IdentifyEvent] {
        events.compactMap { $0 as? IdentifyEvent }
    }

    func filterDeviceDeleted(_ events: [RawEvent]) -> [RawEvent] {
        events.filter { ($0 as? TrackEvent)?.event == "Device Deleted" }
    }

    func filterDeviceCreated(_ events: [RawEvent]) -> [RawEvent] {
        events.filter { ($0 as? TrackEvent)?.event == "Device Created or Updated" }
    }
}
