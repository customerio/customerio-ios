@testable import CioInternalCommon
import SharedTests
import XCTest

class EventStorageTest: UnitTest {
    var eventStorageManager: EventStorageManager!

    override func setUp() {
        super.setUp()
        if let tempDirectory = createTemporaryDirectory() {
            eventStorageManager = EventStorageManager()
            eventStorageManager.updateBaseDirectory(baseDirectory: tempDirectory)
        }
    }

    override func tearDown() {
        eventStorageManager = nil
        super.tearDown()
    }

    func createTemporaryDirectory() -> URL? {
        let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let uniqueDirectoryURL = temporaryDirectoryURL.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: uniqueDirectoryURL, withIntermediateDirectories: true)
            return uniqueDirectoryURL
        } catch {
            print("Failed to create temporary directory: \(error)")
            return nil
        }
    }

    func testStoreEvent() {
        let event = ProfileIdentifiedEvent(identifier: "testID")

        XCTAssertNoThrow(try eventStorageManager.store(event: event), "Storing event should not throw an error")

        let eventFileURL = eventStorageManager.baseDirectory.appendingPathComponent(ProfileIdentifiedEvent.key).appendingPathComponent("\(event.storageId).json")
        let fileExists = FileManager.default.fileExists(atPath: eventFileURL.path)
        XCTAssertTrue(fileExists, "Event file should exist after storing")
    }

    func testLoadStoredEvents() {
        let event = ProfileIdentifiedEvent(identifier: "testID")
        try? eventStorageManager.store(event: event)

        let loadedEvents = try? eventStorageManager.loadEvents(ofType: ProfileIdentifiedEvent.key)
        let containsEvent = loadedEvents?.contains(where: { ($0 as? ProfileIdentifiedEvent)?.identifier == "testID" }) ?? false
        XCTAssertTrue(containsEvent, "Loaded events should contain the stored event")
    }

    func testRemoveEvent() {
        let event = ProfileIdentifiedEvent(identifier: "testID")
        try? eventStorageManager.store(event: event)

        let eventFileURL = eventStorageManager.baseDirectory.appendingPathComponent(ProfileIdentifiedEvent.key).appendingPathComponent("\(event.storageId).json")
        XCTAssertNoThrow(eventStorageManager.remove(ofType: ProfileIdentifiedEvent.key, withStorageId: event.storageId), "Removing event should not throw an error")

        let fileExists = FileManager.default.fileExists(atPath: eventFileURL.path)
        XCTAssertFalse(fileExists, "Event file should not exist after removal")
    }

    func testLoadEventsOfNonexistentType() {
        let loadedEvents = try? eventStorageManager.loadEvents(ofType: "NonexistentType")
        let isEmpty = loadedEvents?.isEmpty ?? false
        XCTAssertTrue(isEmpty, "Loading events for a nonexistent type should return an empty array")
    }

    func testLoadEventsWhenDirectoryDoesNotExist() {
        let nonExistentEventType = "NonExistentEvent"
        let loadedEvents = try? eventStorageManager.loadEvents(ofType: nonExistentEventType)
        XCTAssertTrue(loadedEvents?.isEmpty ?? false, "Loading events for a non-existent directory should return an empty array")
    }

    func testRemoveEventWhenFileDoesNotExist() {
        let eventType = ProfileIdentifiedEvent.key
        let nonExistentStorageId = UUID().uuidString
        XCTAssertNoThrow(eventStorageManager.remove(ofType: eventType, withStorageId: nonExistentStorageId), "Removing a non-existent event should not throw an error")
    }

    func testStoreCreatesDirectoryIfNeeded() {
        let event = ResetEvent() // Assume this is a new event type
        XCTAssertNoThrow(try eventStorageManager.store(event: event), "Storing event should not throw an error")

        let eventTypeDirectory = eventStorageManager.baseDirectory.appendingPathComponent(ResetEvent.key)
        let directoryExists = FileManager.default.fileExists(atPath: eventTypeDirectory.path)
        XCTAssertTrue(directoryExists, "Event storage should create the directory if it does not exist")
    }

    func testLoadEventsWithCorruptDataContinuesLoading() {
        // Store a corrupt event file manually
        let corruptData = Data("corrupt data".utf8)
        let eventTypeDirectory = eventStorageManager.baseDirectory.appendingPathComponent(ProfileIdentifiedEvent.key)
        let corruptFileURL = eventTypeDirectory.appendingPathComponent("corruptEvent.json")
        try? corruptData.write(to: corruptFileURL)

        // Store a valid event file
        let validEvent = ProfileIdentifiedEvent(identifier: "testID")
        try? eventStorageManager.store(event: validEvent)

        // Attempt to load events
        var loadedEvents: [AnyEventRepresentable] = []
        XCTAssertNoThrow(loadedEvents = try eventStorageManager.loadEvents(ofType: ProfileIdentifiedEvent.key), "Loading events should not throw an error even with corrupt data present")

        // Check if the valid event is loaded
        let containsValidEvent = loadedEvents.contains(where: { ($0 as? ProfileIdentifiedEvent)?.identifier == "testID" })
        XCTAssertTrue(containsValidEvent, "Valid events should be loaded even if corrupt data is present")

        // Optionally, you can also check the logs or any error handling mechanism you implemented for the caught errors
    }
}
