@testable import CioDataPipelines
@testable import CioInternalCommon
import Foundation
@testable import Segment
@testable import SharedTests
import XCTest

private typealias SavedEvent = [String: Any]

class DataPipelineCompatibilityTests: IntegrationTest {
    private var storage: Storage!
    private var dataPipelineImplementation: DataPipelineImplementation!

    private let eventBusHandlerMock = EventBusHandlerMock()
    private let globalDataStoreMock = GlobalDataStoreMock()

    override func setUpDependencies() {
        super.setUpDependencies()

        diGraphShared.override(value: eventBusHandlerMock, forType: EventBusHandler.self)
        diGraphShared.override(value: globalDataStoreMock, forType: GlobalDataStore.self)
    }

    override func setUp() {
        super.setUp(modifyModuleConfig: { config in
            // enable auto add destination so we can test the final JSON being sent to the server
            config.autoAddCustomerIODestination = true
        })
        
        // get DataPipelineImplementation instance so we can call its methods directly
        dataPipelineImplementation = (customerIO.implementation as! DataPipelineImplementation)

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
        XCTAssertTrue(savedEvent[mapKeyPath: "traits"]?.isEmpty ?? false)
    }

    func test_identifyWithAttributes_expectFinalJSONHasCorrectKeysAndValues() {
        let givenIdentifier = String.random
        let givenBody: [String: Any] = ["first_name": "Dana", "age": 30]

        customerIO.identify(identifier: givenIdentifier, body: givenBody)

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
        let expectedData = deviceInfoStub.getDefaultAttributes()

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

        XCTAssertMatches(savedEvent[mapKeyPath: "properties"], expectedData)
    }

    func test_setDeviceAttributes_expectFinalJSONHasCorrectKeysAndValues() {
        let givenIdentifier = String.random
        let givenToken = String.random
        let customAttributes: [String: Any] = [
            "source": "test",
            "debugMode": true
        ]
        let expectedData = deviceInfoStub.getDefaultAttributes().mergeWith(customAttributes)

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

        XCTAssertMatches(
            savedEvent[mapKeyPath: "properties"],
            expectedData,
            withTypeMap: [["debugMode"]: Bool.self]
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
        customerIO.track(name: givenEvent, data: givenData)

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
        XCTAssertTrue(savedEvent[mapKeyPath: "properties"]?.isEmpty ?? false)
    }

    func test_screenWithAttributes_expectFinalJSONHasCorrectKeysAndValues() {
        let givenScreen = String.random
        let givenData: [String: Any] = ["first_name": "Dana", "age": 30]

        customerIO.identify(userId: String.random)
        customerIO.screen(name: givenScreen, data: givenData)

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
            "action_name": "TestClick",
            "action_value": "Test"
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

    func readTypeFromStorage(writeKey: String? = nil, key: Storage.Constants) -> [SavedEvent] {
        guard let results = storage.read(key) else { return [] }

        return results.flatMap { result -> [SavedEvent] in
            guard let content = readFileFromURL(result),
                  let dict = convertJSONStringToSavedEvent(content),
                  let batch = dict["batch"] as? [SavedEvent],
                  writeKey == nil || writeKey == dict["writeKey"] as? String
            else {
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
