import Foundation

/// Defines the protocol for event storage management.
///
/// This protocol specifies the methods for storing, loading, and removing events,
/// facilitating the management of event persistence.
public protocol EventStorage: AutoMockable {
    /// Stores an event asynchronously.
    /// - Parameter event: The event to be stored.
    func store(event: AnyEventRepresentable) async throws
    /// Retrieves a specific event asynchronously using its type and unique identifier.
    /// - Parameters:
    ///   - eventType: The type of the event to retrieve.
    ///   - identifier: The unique identifier of the event.
    /// - Returns: The event of the specified type if found otherwise nil
    func retrieve(eventType: String, storageId: String) async throws -> AnyEventRepresentable?
    /// Loads all events of a specific type asynchronously.
    /// - Parameter type: The type of events to load.
    /// - Returns: An array of events of the specified type.
    func loadEvents(ofType type: String) async throws -> [AnyEventRepresentable]
    /// Removes a specific event asynchronously by its storage identifier.
    /// - Parameters:
    ///   - eventType: The type of the event.
    ///   - storageId: The unique identifier of the event to remove.
    func remove(ofType eventType: String, withStorageId storageId: String) async
    /// Removes all event asynchronously from current storage.
    ///
    /// The function can be used for cleaning up or resetting the event handling system.
    func removeAll() async
}

/// Errors related to event bus operations.
enum EventBusError: Error {
    case invalidEventType
    case decodingError
}

// swiftlint:disable orphaned_doc_comment
/// An actor that manages event storage, providing thread-safe operations for storing, loading, and removing events.
///
/// This class handles the persistence of events using the file system, ensuring data integrity and consistency.
// sourcery: InjectRegisterShared = "EventStorage"
// sourcery: InjectSingleton
// swiftlint:enable orphaned_doc_comment
actor EventStorageManager: EventStorage {
    private let fileManager = FileManager.default
    public var baseDirectory: URL
    private let logger: Logger
    private let jsonAdapter: JsonAdapter

    /// Initializes the EventStorageManager with the necessary dependencies.
    /// - Parameters:
    ///   - logger: A logger for logging information and errors.
    ///   - jsonAdapter: A JSON adapter for encoding and decoding events.
    init(logger: Logger, jsonAdapter: JsonAdapter) {
        let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.baseDirectory = documentDirectory.appendingPathComponent("Events")
        self.logger = logger
        self.jsonAdapter = jsonAdapter
    }

    /// Updates the base directory for event storage, primarily used for testing.
    /// - Parameter baseDirectory: The new base directory for storing events.
    func updateBaseDirectory(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    func store(event: AnyEventRepresentable) throws {
        let eventTypeDirectory = baseDirectory.appendingPathComponent(event.key)
        try createDirectoryIfNeeded(eventTypeDirectory)

        let eventFileURL = eventTypeDirectory.appendingPathComponent("\(event.storageId).json")
        let eventData = try jsonAdapter.encoder.encode(event)
        try eventData.write(to: eventFileURL)
    }

    func retrieve(eventType: String, storageId: String) async throws -> AnyEventRepresentable? {
        // Construct the file path based on the event type and storageId
        let fileURL = baseDirectory
            .appendingPathComponent(eventType)
            .appendingPathComponent("\(storageId).json")

        // Check if the file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        // Read the data from the file
        let data = try Data(contentsOf: fileURL)
        let eventTypeClass = try EventTypesRegistry.getEventType(for: eventType)
        let event = try jsonAdapter.decoder.decode(eventTypeClass, from: data)

        return event
    }

    func loadEvents(ofType eventType: String) throws -> [AnyEventRepresentable] {
        let eventTypeDirectory = baseDirectory.appendingPathComponent(eventType)
        guard fileManager.fileExists(atPath: eventTypeDirectory.path) else { return [] }

        let fileURLs = try fileManager.contentsOfDirectory(at: eventTypeDirectory, includingPropertiesForKeys: nil)
        let eventTypeClass = try EventTypesRegistry.getEventType(for: eventType)

        var events: [AnyEventRepresentable] = []
        for url in fileURLs {
            let data = try Data(contentsOf: url)
            do {
                let event = try jsonAdapter.decoder.decode(eventTypeClass, from: data)
                events.append(event)
            } catch {
                logger.error("Warning: Could not decode event at \(url). Error: \(error)")
            }
        }
        // Sort events based on their timestamp.
        return events.sorted(by: { $0.timestamp < $1.timestamp })
    }

    // Removes a specific event file
    func remove(ofType eventType: String, withStorageId storageId: String) {
        let eventFileURL = baseDirectory.appendingPathComponent(eventType).appendingPathComponent("\(storageId).json")
        do {
            try fileManager.removeItem(at: eventFileURL)
        } catch {
            logger.error("Warning: Could not remove event file at \(eventFileURL). Error: \(error)")
        }
    }

    /// Creates a directory at the specified URL if it does not already exist.
    /// - Parameter directory: The directory URL to create.
    private func createDirectoryIfNeeded(_ directory: URL) throws {
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func removeAll() async {
        try? fileManager.removeItem(at: baseDirectory)
    }
}
