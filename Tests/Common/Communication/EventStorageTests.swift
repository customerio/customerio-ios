@testable import CioInternalCommon
import SharedTests
import XCTest

class EventStorageTest: UnitTest {
    var eventStorageManager: EventStorageManager!

    override func setUpDependencies() {
        super.setUpDependencies()

        eventStorageManager = EventStorageManager(logger: log, jsonAdapter: jsonAdapter)
        diGraphShared.override(value: eventStorageManager, forType: EventStorage.self)
    }

    // MARK: - Event Storage Tests

    func test_storeEvent_givenValidEvent_expectEventPersisted() async throws {
        // Storing the event using the first instance of EventStorageManager
        let event = ProfileIdentifiedEvent(identifier: "testID")
        try await eventStorageManager.store(event: event)

        // Creating a new instance of EventStorageManager for retrieving the event
        let newEventStorageManager = EventStorageManager(logger: log, jsonAdapter: jsonAdapter)
        await newEventStorageManager.updateBaseDirectory(baseDirectory: eventStorageManager.baseDirectory)

        let retrievedEvent = try await newEventStorageManager.retrieve(eventType: event.key, storageId: event.storageId)

        XCTAssertEqual(retrievedEvent?.storageId, event.storageId, "Retrieved event should match the stored event")
    }

    func test_storeEvent_givenNewEventType_expectDirectoryCreated() async throws {
        // Store an event of a new type
        let event = ScreenViewedEvent(name: String.random) // Assume this is a new event type
        try await eventStorageManager.store(event: event)

        // Retrieve the stored event
        let retrievedEvent = try await eventStorageManager.retrieve(eventType: event.key, storageId: event.storageId) as? ScreenViewedEvent

        // Assert that the retrieved event matches the stored event
        XCTAssertEqual(retrievedEvent?.name, event.name, "Retrieved event should match the stored event for the new event type")
    }

    // MARK: - Event Retrieval Tests

    func test_loadEvents_givenStoredEvent_expectEventLoaded() async throws {
        let event = ProfileIdentifiedEvent(identifier: "testID")
        try await eventStorageManager.store(event: event)

        let loadedEvents = try await eventStorageManager.loadEvents(ofType: ProfileIdentifiedEvent.key)
        let containsEvent = loadedEvents.contains { ($0 as? ProfileIdentifiedEvent)?.identifier == "testID" }
        XCTAssertTrue(containsEvent, "Loaded events should contain the stored event")
    }

    func test_loadEvents_givenNonExistentDirectory_expectEmptyArray() async throws {
        let nonExistentEventType = "NonExistentEvent"
        let loadedEvents = try await eventStorageManager.loadEvents(ofType: nonExistentEventType)
        XCTAssertTrue(loadedEvents.isEmpty, "Loading events for a non-existent directory should return an empty array")
    }

    func test_loadEvents_givenNonexistentEventType_expectEmptyArray() async throws {
        let loadedEvents = try await eventStorageManager.loadEvents(ofType: "NonexistentType")
        XCTAssertTrue(loadedEvents.isEmpty, "Loading events for a nonexistent type should return an empty array")
    }

    func test_loadEvents_givenCorruptDataInFile_expectValidEventsLoaded() async throws {
        // Ensure the directory for the event type exists
        let eventTypeDirectory = await eventStorageManager.baseDirectory.appendingPathComponent(ProfileIdentifiedEvent.key)
        try FileManager.default.createDirectory(at: eventTypeDirectory, withIntermediateDirectories: true)

        // Store a corrupt event file manually
        let corruptData = Data("corrupt data".utf8)
        let corruptFileURL = eventTypeDirectory.appendingPathComponent("corruptEvent.json")
        try corruptData.write(to: corruptFileURL)

        // Store a valid event file
        let validEvent = ProfileIdentifiedEvent(identifier: "testID")
        try await eventStorageManager.store(event: validEvent)

        // Attempt to load events
        let loadedEvents = try await eventStorageManager.loadEvents(ofType: ProfileIdentifiedEvent.key)
        let containsValidEvent = loadedEvents.contains { ($0 as? ProfileIdentifiedEvent)?.identifier == "testID" }
        XCTAssertTrue(containsValidEvent, "Valid events should be loaded even if corrupt data is present")
    }

    // MARK: - Event Removal Tests

    func test_removeEvent_givenStoredEvent_expectEventRemoved() async throws {
        let event = ProfileIdentifiedEvent(identifier: "testID")
        try await eventStorageManager.store(event: event)

        let eventFileURL = await eventStorageManager.baseDirectory
            .appendingPathComponent(ProfileIdentifiedEvent.key)
            .appendingPathComponent("\(event.storageId).json")
        await eventStorageManager.remove(ofType: ProfileIdentifiedEvent.key, withStorageId: event.storageId)

        let fileExists = FileManager.default.fileExists(atPath: eventFileURL.path)
        XCTAssertFalse(fileExists, "Event file should not exist after removal")
    }

    func test_removeEvent_givenNonExistentFile_expectNoErrorThrown() async throws {
        let eventType = ProfileIdentifiedEvent.key
        let nonExistentStorageId = UUID().uuidString
        await eventStorageManager.remove(ofType: eventType, withStorageId: nonExistentStorageId)
        // If no error is thrown, the test passes
    }

    // MARK: - Concurrency and Ordering Tests

    func test_concurrentEventStorageAndRetrieval_givenMultipleEvents_expectAllEventsStoredAndRetrieved() async throws {
        // Create multiple events
        let events = (1 ... 10).map { ProfileIdentifiedEvent(identifier: "\($0)") }

        // Concurrently store events
        await withThrowingTaskGroup(of: Void.self) { group in
            for event in events {
                group.addTask {
                    try await self.eventStorageManager.store(event: event)
                }
            }
        }

        // Load events and verify
        let loadedEvents = try await eventStorageManager.loadEvents(ofType: ProfileIdentifiedEvent.key)
        XCTAssertEqual(loadedEvents.count, events.count, "All stored events should be retrieved")
    }

    func test_eventOrdering_givenSequentiallyStoredEvents_expectEventsRetrievedInStoredOrder() async throws {
        // Store events in a specific order
        var events = [ProfileIdentifiedEvent]()

        for i in 1 ... 5 {
            let event = ProfileIdentifiedEvent(identifier: "Event\(i)")
            events.append(event)
            // Adding a delay of 1 second. This is necessary because each event includes a timestamp
            // created with Date(), which has a precision up to the second. The delay ensures that
            // each event has a distinct timestamp.
            try await Task.sleep(nanoseconds: 1000000000)
        }

        for event in events {
            try await eventStorageManager.store(event: event)
        }

        // Load events and check order
        let loadedEvents = try await eventStorageManager.loadEvents(ofType: ProfileIdentifiedEvent.key)
        let loadedIdentifiers = loadedEvents.compactMap { ($0 as? ProfileIdentifiedEvent)?.identifier }
        XCTAssertEqual(loadedIdentifiers, events.map(\.identifier), "Events should be loaded in the order they were stored")
    }
}
