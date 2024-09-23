@testable import CioAnalytics
@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
@testable import SharedTests
import XCTest

private typealias SavedEvent = [String: Any]

class DataPipelineCompatibilityTests: IntegrationTest {
    private var storage: Storage!
    private var dataPipelineImplementation: DataPipelineImplementation!

    private let eventBusHandlerMock = EventBusHandlerMock()
    private let globalDataStoreMock = GlobalDataStoreMock()
    private var userAgentUtil: UserAgentUtil?

    override func setUpDependencies() {
        super.setUpDependencies()

        diGraphShared.override(value: eventBusHandlerMock, forType: EventBusHandler.self)
        diGraphShared.override(value: globalDataStoreMock, forType: GlobalDataStore.self)
    }

    override func setUp() {
        super.setUp(modifySdkConfig: { config in
            // enable auto add destination so we can test the final JSON being sent to the server
            config.autoAddCustomerIODestination(true)
        })

        // get DataPipelineImplementation instance so we can call its methods directly
        dataPipelineImplementation = (customerIO.implementation as! DataPipelineImplementation) // swiftlint:disable:this force_cast

        userAgentUtil = UserAgentUtilImpl(deviceInfo: deviceInfoStub, sdkClient: diGraphShared.sdkClient)

        // get storage instance so we can read final events
        storage = analytics.storage
        storage.hardReset(doYouKnowHowToUseThis: true)
    }

    // MARK: profile

    func test_identifyWithoutAttributes_expectFinalJSONHasCorrectKeysAndValues() {
        let givenIdentifier = String.random

        customerIO.identify(userId: givenIdentifier)

        let allEvents = readTypeFromStorage(key: Storage.Constants.events)
        let filteredEvents = allEvents.filter { $0.eventType == "identify" }
        XCTAssertEqual(filteredEvents.count, 1, "too many events received")

        guard let savedEvent = filteredEvents.last else {
            XCTFail("saved event must not be nil")
            return
        }

        XCTAssertEqual(savedEvent[keyPath: "userId"] as? String, givenIdentifier)
        XCTAssertNil(savedEvent[mapKeyPath: "traits"])
    }

    func test_identifyWithAttributes_expectFinalJSONHasCorrectKeysAndValues() {
        let givenIdentifier = String.random
        let givenBody: [String: Any] = ["first_name": "Dana", "age": 30]

        customerIO.identify(userId: givenIdentifier, traits: givenBody)

        let allEvents = readTypeFromStorage(key: Storage.Constants.events)
        let filteredEvents = allEvents.filter { $0.eventType == "identify" }
        XCTAssertEqual(filteredEvents.count, 1, "too many events received")

        guard let savedEvent = filteredEvents.last else {
            XCTFail("saved event must not be nil")
            return
        }

        XCTAssertEqual(savedEvent[keyPath: "userId"] as? String, givenIdentifier)
        XCTAssertMatches(
            savedEvent[mapKeyPath: "traits"],
            givenBody,
            withTypeMap: [["age"]: Int.self]
        )
    }

    func test_eventBeforeIdentify_expectFinalJSONHasNoUserId() {
        let givenEvent = String.random

        customerIO.track(name: givenEvent)

        let allEvents = readTypeFromStorage(key: Storage.Constants.events)
        let filteredEvents = allEvents.filter { $0.eventType == "track" }
        XCTAssertEqual(filteredEvents.count, 1, "too many events received")

        guard let savedEvent = filteredEvents.last else {
            XCTFail("saved event must not be nil")
            return
        }

        XCTAssertNil(savedEvent[keyPath: "userId"] as? String)
        XCTAssertNotNil(savedEvent[keyPath: "anonymousId"] as? String)
    }

    func test_eventAfterIdentify_expectFinalJSONHasCorrectUserId() {
        let givenIdentifier = String.random
        let givenEvent = String.random

        customerIO.identify(userId: givenIdentifier)
        customerIO.track(name: givenEvent)

        let allEvents = readTypeFromStorage(key: Storage.Constants.events)
        let filteredEvents = allEvents.filter { $0.eventType == "track" }
        XCTAssertEqual(filteredEvents.count, 1, "too many events received")

        guard let savedEvent = filteredEvents.last else {
            XCTFail("saved event must not be nil")
            return
        }

        XCTAssertEqual(savedEvent[keyPath: "userId"] as? String, givenIdentifier)
    }

    // MARK: device

    func test_registerDeviceToken_expectFinalJSONHasCorrectKeysAndValues() {
        let givenIdentifier = String.random
        let givenToken = String.random
        let givenDefaultAttributes = deviceInfoStub.getDefaultAttributes()

        customerIO.identify(userId: givenIdentifier)
        customerIO.registerDeviceToken(givenToken)

        let allEvents = readTypeFromStorage(key: Storage.Constants.events)
        let filteredEvents = allEvents.filter { $0.eventType == "track" }
        XCTAssertEqual(filteredEvents.count, 1, "too many events received")

        guard let savedEvent = filteredEvents.first else {
            XCTFail("saved event must not be nil")
            return
        }

        XCTAssertEqual(savedEvent[keyPath: "event"] as? String, "Device Created or Updated")
        XCTAssertEqual(savedEvent[keyPath: "userId"] as? String, givenIdentifier)
        XCTAssertEqual(savedEvent[keyPath: "context.device.token"] as? String, givenToken)
        XCTAssertEqual(savedEvent[keyPath: "context.device.type"] as? String, "ios")
        // server does not require 'last_used' and 'platform' and may fail if included
        XCTAssertFalse(savedEvent.containsKey("last_used"))
        XCTAssertFalse(savedEvent.containsKey("platform"))

        var expectedData = givenDefaultAttributes
        expectedData["cio_sdk_version"] = diGraphShared.sdkClient.sdkVersion
        expectedData.merge(
            // swiftlint:disable:next force_cast
            (savedEvent[keyPath: "context.screen"] as! [String: Any]).flatten(parentKey: "screen"),
            uniquingKeysWith: { current, _ in current }
        )
        expectedData.merge(
            // swiftlint:disable:next force_cast
            (savedEvent[keyPath: "context.network"] as! [String: Any]).flatten(parentKey: "network"),
            uniquingKeysWith: { current, _ in current }
        )
        expectedData["timezone"] = savedEvent[keyPath: "context.timezone"] as? String
        expectedData["ip"] = savedEvent[keyPath: "context.ip"] as? String

        XCTAssertMatches(
            savedEvent[mapKeyPath: "properties"],
            expectedData,
            withTypeMap: [
                ["network_bluetooth", "network_cellular", "network_wifi"]: Bool.self,
                ["screen_height", "screen_width"]: Int.self
            ]
        )
    }

    func test_setDeviceAttributes_expectFinalJSONHasCorrectKeysAndValues() {
        let givenIdentifier = String.random
        let givenToken = String.random
        let customAttributes: [String: Any] = [
            "source": "test",
            "debugMode": true
        ]

        customerIO.identify(userId: givenIdentifier)
        customerIO.registerDeviceToken(givenToken)
        customerIO.deviceAttributes = customAttributes

        let allEvents = readTypeFromStorage(key: Storage.Constants.events)
        let filteredEvents = allEvents.filter { $0.eventType == "track" }
        XCTAssertEqual(filteredEvents.count, 2, "too many events received")

        guard let savedEvent = filteredEvents.last else {
            XCTFail("saved event must not be nil")
            return
        }

        XCTAssertEqual(savedEvent[keyPath: "event"] as? String, "Device Created or Updated")
        XCTAssertEqual(savedEvent[keyPath: "userId"] as? String, givenIdentifier)
        XCTAssertEqual(savedEvent[keyPath: "context.device.token"] as? String, givenToken)

        var expectedData = deviceInfoStub.getDefaultAttributes().mergeWith(customAttributes)
        expectedData["cio_sdk_version"] = diGraphShared.sdkClient.sdkVersion
        expectedData.merge(
            // swiftlint:disable:next force_cast
            (savedEvent[keyPath: "context.screen"] as! [String: Any]).flatten(parentKey: "screen"),
            uniquingKeysWith: { current, _ in current }
        )
        expectedData.merge(
            // swiftlint:disable:next force_cast
            (savedEvent[keyPath: "context.network"] as! [String: Any]).flatten(parentKey: "network"),
            uniquingKeysWith: { current, _ in current }
        )
        expectedData["timezone"] = savedEvent[keyPath: "context.timezone"] as? String
        expectedData["ip"] = savedEvent[keyPath: "context.ip"] as? String

        XCTAssertMatches(
            savedEvent[mapKeyPath: "properties"],
            expectedData,
            withTypeMap: [
                ["network_bluetooth", "network_cellular", "network_wifi", "debugMode"]: Bool.self,
                ["screen_height", "screen_width"]: Int.self
            ]
        )
    }

    func test_deleteDeviceToken_expectFinalJSONHasCorrectKeysAndValues() {
        let givenIdentifier = String.random
        let givenToken = String.random

        customerIO.identify(userId: givenIdentifier)
        customerIO.registerDeviceToken(givenToken)

        // clearIdentify calls deleteDeviceToken internally
        customerIO.clearIdentify()

        let allEvents = readTypeFromStorage(key: Storage.Constants.events)
        let filteredEvents = allEvents.filter { $0.eventType == "track" }
        XCTAssertEqual(filteredEvents.count, 2, "too many events received")

        guard let savedEvent = filteredEvents.last else {
            XCTFail("saved event must not be nil")
            return
        }

        XCTAssertEqual(savedEvent[keyPath: "event"] as? String, "Device Deleted")
        XCTAssertEqual(savedEvent[keyPath: "userId"] as? String, givenIdentifier)
        XCTAssertEqual(savedEvent[keyPath: "context.device.token"] as? String, givenToken)
        XCTAssertNil(savedEvent[keyPath: "properties"])
    }

    // MARK: event

    func test_anyEvent_expectFinalJsonHasCorrectUserAgent() {
        let givenUserAgent = userAgentUtil?.getUserAgentHeaderValue()
        let givenEvent = String.random
        customerIO.track(name: givenEvent)

        let allEvents = readTypeFromStorage(key: Storage.Constants.events)
        let filteredEvents = allEvents.filter { $0.eventType == "track" }
        XCTAssertEqual(filteredEvents.count, 1, "too many events received")

        guard let savedEvent = filteredEvents.last else {
            XCTFail("saved event must not be nil")
            return
        }

        guard let userAgent = givenUserAgent else {
            XCTFail("user agent must not be nil")
            return
        }

        XCTAssertEqual(savedEvent[keyPath: "event"] as? String, givenEvent)
        XCTAssertEqual(savedEvent[keyPath: "context.userAgent"] as? String, userAgent)
    }

    func test_anyEvent_expectFinalJsonDoesNotHaveLibrary() {
        let givenUserAgent = userAgentUtil?.getUserAgentHeaderValue()
        let givenEvent = String.random
        customerIO.track(name: givenEvent)

        let allEvents = readTypeFromStorage(key: Storage.Constants.events)
        let filteredEvents = allEvents.filter { $0.eventType == "track" }
        XCTAssertEqual(filteredEvents.count, 1, "too many events received")

        guard let savedEvent = filteredEvents.last else {
            XCTFail("saved event must not be nil")
            return
        }

        guard givenUserAgent != nil else {
            XCTFail("user agent must not be nil")
            return
        }

        XCTAssertEqual(savedEvent[keyPath: "event"] as? String, givenEvent)
        XCTAssertNil(savedEvent[keyPath: "context.library"])
    }

    func test_eventWithoutAttributes_expectFinalJSONHasCorrectKeysAndValues() {
        let givenEvent = String.random

        customerIO.identify(userId: String.random)
        customerIO.track(name: givenEvent)

        let allEvents = readTypeFromStorage(key: Storage.Constants.events)
        let filteredEvents = allEvents.filter { $0.eventType == "track" }
        XCTAssertEqual(filteredEvents.count, 1, "too many events received")

        guard let savedEvent = filteredEvents.last else {
            XCTFail("saved event must not be nil")
            return
        }

        XCTAssertEqual(savedEvent[keyPath: "event"] as? String, givenEvent)
        XCTAssertNil(savedEvent[keyPath: "properties"])
    }

    func test_eventWithAttributes_expectFinalJSONHasCorrectKeysAndValues() {
        let givenEvent = String.random
        let givenData: [String: Any] = ["first_name": "Dana", "age": 30]

        customerIO.identify(userId: String.random)
        customerIO.track(name: givenEvent, properties: givenData)

        let allEvents = readTypeFromStorage(key: Storage.Constants.events)
        let filteredEvents = allEvents.filter { $0.eventType == "track" }
        XCTAssertEqual(filteredEvents.count, 1, "too many events received")

        guard let savedEvent = filteredEvents.last else {
            XCTFail("saved event must not be nil")
            return
        }

        XCTAssertEqual(savedEvent[keyPath: "event"] as? String, givenEvent)
        XCTAssertMatches(
            savedEvent[mapKeyPath: "properties"],
            givenData,
            withTypeMap: [["age"]: Int.self]
        )
    }

    // MARK: screen

    func test_screenWithoutAttributes_expectFinalJSONHasCorrectKeysAndValues() {
        let givenScreen = String.random

        customerIO.identify(userId: String.random)
        customerIO.screen(title: givenScreen)

        let allEvents = readTypeFromStorage(key: Storage.Constants.events)
        let filteredEvents = allEvents.filter { $0.eventType == "screen" }
        XCTAssertEqual(filteredEvents.count, 1, "too many events received")

        guard let savedEvent = filteredEvents.last else {
            XCTFail("saved event must not be nil")
            return
        }

        XCTAssertEqual(savedEvent[keyPath: "name"] as? String, givenScreen)
        XCTAssertNil(savedEvent[keyPath: "properties"])
    }

    func test_screenWithAttributes_expectFinalJSONHasCorrectKeysAndValues() {
        let givenScreen = String.random
        let givenData: [String: Any] = ["first_name": "Dana", "age": 30]

        customerIO.identify(userId: String.random)
        customerIO.screen(title: givenScreen, properties: givenData)

        let allEvents = readTypeFromStorage(key: Storage.Constants.events)
        let filteredEvents = allEvents.filter { $0.eventType == "screen" }
        XCTAssertEqual(filteredEvents.count, 1, "too many events received")

        guard let savedEvent = filteredEvents.last else {
            XCTFail("saved event must not be nil")
            return
        }

        XCTAssertEqual(savedEvent[keyPath: "name"] as? String, givenScreen)
        XCTAssertMatches(
            savedEvent[mapKeyPath: "properties"],
            givenData,
            withTypeMap: [["age"]: Int.self]
        )
    }

    // MARK: metrics

    func test_pushMetrics_expectFinalJSONHasCorrectKeysAndValues() {
        let givenDeliveryID = String.random
        let givenMetric = Metric.delivered.rawValue
        let givenDeviceToken = String.random

        let expectedData: [String: Any] = [
            "metric": givenMetric,
            "deliveryId": givenDeliveryID,
            "recipient": givenDeviceToken
        ]

        customerIO.identify(userId: String.random)

        dataPipelineImplementation.trackPushMetric(deliveryID: givenDeliveryID, event: givenMetric, deviceToken: givenDeviceToken)

        let allEvents = readTypeFromStorage(key: Storage.Constants.events)
        let filteredEvents = allEvents.filter { $0.eventType == "track" }
        XCTAssertEqual(filteredEvents.count, 1, "too many events received")

        guard let savedEvent = filteredEvents.last else {
            XCTFail("saved event must not be nil")
            return
        }

        XCTAssertEqual(savedEvent[keyPath: "event"] as? String, "Report Delivery Event")
        XCTAssertMatches(savedEvent[mapKeyPath: "properties"], expectedData)
    }

    func test_inAppMetrics_expectFinalJSONHasCorrectKeysAndValues() {
        let givenDeliveryID = String.random
        let givenMetric = Metric.delivered.rawValue
        let givenMetaData: [String: String] = [
            "actionName": "TestClick",
            "actionValue": "Test"
        ]

        let expectedData: [String: Any] = [
            "metric": givenMetric,
            "deliveryId": givenDeliveryID
        ].mergeWith(givenMetaData)

        customerIO.identify(userId: String.random)

        dataPipelineImplementation.trackInAppMetric(deliveryID: givenDeliveryID, event: givenMetric, metaData: givenMetaData)

        let allEvents = readTypeFromStorage(key: Storage.Constants.events)
        let filteredEvents = allEvents.filter { $0.eventType == "track" }
        XCTAssertEqual(filteredEvents.count, 1, "too many events received")

        guard let savedEvent = filteredEvents.last else {
            XCTFail("saved event must not be nil")
            return
        }

        XCTAssertEqual(savedEvent[keyPath: "event"] as? String, "Report Delivery Event")
        XCTAssertMatches(savedEvent[mapKeyPath: "properties"], expectedData)
    }
}

private extension DataPipelineCompatibilityTests {
    func readFileFromURL(_ url: URL?) -> String? {
        guard let url = url else { return nil }

        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            return contents
        } catch {
            print("Error reading file: \(error)")
            return nil
        }
    }

    func convertJSONStringToSavedEvent(_ jsonString: String) -> SavedEvent? {
        guard let data = jsonString.data(using: .utf8) else {
            print("Error: Cannot create data from string")
            return nil
        }

        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            if let savedEvent = jsonObject as? SavedEvent {
                return savedEvent
            } else {
                print("Error: JSON is not a dictionary")
                return nil
            }
        } catch {
            print("Error: \(error)")
            return nil
        }
    }

    func readTypeFromStorage(cdpApiKey: String? = nil, key: Storage.Constants) -> [SavedEvent] {
        guard let results = storage.read(key),
              let files = results.dataFiles else { return [] }

        return files.flatMap { result -> [SavedEvent] in
            guard let content = readFileFromURL(result),
                  let dict = convertJSONStringToSavedEvent(content),
                  let batch = dict["batch"] as? [SavedEvent]
            else {
                return []
            }

            if let apiKey = cdpApiKey, apiKey != dict["writeKey"] as? String {
                return []
            }

            return batch
        }
    }
}

private extension SavedEvent {
    var eventType: String? { self[keyPath: "type"] as? String }
    subscript(mapKeyPath keyPath: KeyPath) -> [String: Any]? { value(keyPath: keyPath, reference: nil) as? [String: Any] }

    /// checks recursively if a given key exists anywhere in the event
    func containsKey(_ key: String) -> Bool {
        for (_, value) in self {
            if let innerDict = value as? [String: Any] {
                if innerDict.keys.contains(key) {
                    return true
                }
                if innerDict.containsKey(key) {
                    return true
                }
            }
        }
        return false
    }
}
