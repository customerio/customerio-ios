@testable import CioInternalCommon
import SharedTests
import XCTest

class EventStorageTest: UnitTest {
    var eventStorageManager: EventStorageManager!

    override func setUp() {
        super.setUp()
        if let tempDirectory = createTemporaryDirectory() {
            eventStorageManager = EventStorageManager(logger: log, jsonAdapter: jsonAdapter)
            Task {
                await eventStorageManager.updateBaseDirectory(baseDirectory: tempDirectory)
            }
        }
    }

    override func tearDown() {
        eventStorageManager = nil
        super.tearDown()
    }

    // MARK: - Helper Methods

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

    // MARK: - Event Storage Tests

    func testStoreEvent() async throws {
        let event = ProfileIdentifiedEvent(identifier: "testID")
        try await eventStorageManager.store(event: event)

        let eventFileURL = await eventStorageManager.baseDirectory
            .appendingPathComponent(ProfileIdentifiedEvent.key)
            .appendingPathComponent("\(event.storageId).json")
        let fileExists = FileManager.default.fileExists(atPath: eventFileURL.path)
        XCTAssertTrue(fileExists, "Event file should exist after storing")
    }

    func testStoreCreatesDirectoryIfNeeded() async throws {
        let event = ResetEvent() // Assume this is a new event type
        try await eventStorageManager.store(event: event)

        let eventTypeDirectory = await eventStorageManager.baseDirectory.appendingPathComponent(ResetEvent.key)
        let directoryExists = FileManager.default.fileExists(atPath: eventTypeDirectory.path)
        XCTAssertTrue(directoryExists, "Event storage should create the directory if it does not exist")
    }

    // MARK: - Event Retrieval Tests

    func testLoadStoredEvents() async throws {
        let event = ProfileIdentifiedEvent(identifier: "testID")
        try await eventStorageManager.store(event: event)

        let loadedEvents = try await eventStorageManager.loadEvents(ofType: ProfileIdentifiedEvent.key)
        let containsEvent = loadedEvents.contains { ($0 as? ProfileIdentifiedEvent)?.identifier == "testID" }
        XCTAssertTrue(containsEvent, "Loaded events should contain the stored event")
    }

    func testLoadEventsWhenDirectoryDoesNotExist() async throws {
        let nonExistentEventType = "NonExistentEvent"
        let loadedEvents = try await eventStorageManager.loadEvents(ofType: nonExistentEventType)
        XCTAssertTrue(loadedEvents.isEmpty, "Loading events for a non-existent directory should return an empty array")
    }

    func testLoadEventsOfNonexistentType() async throws {
        let loadedEvents = try await eventStorageManager.loadEvents(ofType: "NonexistentType")
        XCTAssertTrue(loadedEvents.isEmpty, "Loading events for a nonexistent type should return an empty array")
    }

    func testLoadEventsWithCorruptDataContinuesLoading() async throws {
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

    func testRemoveEvent() async throws {
        let event = ProfileIdentifiedEvent(identifier: "testID")
        try await eventStorageManager.store(event: event)

        let eventFileURL = await eventStorageManager.baseDirectory
            .appendingPathComponent(ProfileIdentifiedEvent.key)
            .appendingPathComponent("\(event.storageId).json")
        await eventStorageManager.remove(ofType: ProfileIdentifiedEvent.key, withStorageId: event.storageId)

        let fileExists = FileManager.default.fileExists(atPath: eventFileURL.path)
        XCTAssertFalse(fileExists, "Event file should not exist after removal")
    }

    func testRemoveEventWhenFileDoesNotExist() async throws {
        let eventType = ProfileIdentifiedEvent.key
        let nonExistentStorageId = UUID().uuidString
        await eventStorageManager.remove(ofType: eventType, withStorageId: nonExistentStorageId)
        // If no error is thrown, the test passes
    }

    // MARK: - Concurrency and Ordering Tests

    func testConcurrentEventStorageAndRetrieval() async throws {
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

    func testEventOrdering() async throws {
        // Store events in a specific order
        let events = (1 ... 5).map { ProfileIdentifiedEvent(identifier: "Event\($0)") }
        for event in events {
            try await eventStorageManager.store(event: event)
        }

        // Load events and check order
        let loadedEvents = try await eventStorageManager.loadEvents(ofType: ProfileIdentifiedEvent.key)
        let loadedIdentifiers = loadedEvents.compactMap { ($0 as? ProfileIdentifiedEvent)?.identifier }
        XCTAssertEqual(loadedIdentifiers, events.map(\.identifier), "Events should be loaded in the order they were stored")
    }
}
