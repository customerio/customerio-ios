import Foundation

public protocol EventStorage: AutoMockable {
    /// Stores an event.
    func store(event: AnyEventRepresentable) async throws
    /// Loads all events of a specific type.
    func loadEvents(ofType type: String) async throws -> [AnyEventRepresentable]
    /// Removes a specific event by its storage identifier.
    func remove(ofType eventType: String, withStorageId storageId: String) async
}

enum EventBusError: Error {
    case invalidEventType
    case decodingError
}

// sourcery: InjectRegisterShared = "EventStorage"
actor EventStorageManager: EventStorage {
    private let fileManager = FileManager.default
    public var baseDirectory: URL
    private let logger: Logger
    private let jsonAdapter: JsonAdapter

    init(logger: Logger, jsonAdapter: JsonAdapter) {
        let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.baseDirectory = documentDirectory.appendingPathComponent("Events")
        self.logger = logger
        self.jsonAdapter = jsonAdapter
    }

    // for testing
    func updateBaseDirectory(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    // Stores an event by creating a JSON file
    func store(event: AnyEventRepresentable) async throws {
        let eventTypeDirectory = baseDirectory.appendingPathComponent(event.key)
        try await createDirectoryIfNeeded(eventTypeDirectory)

        let eventFileURL = eventTypeDirectory.appendingPathComponent("\(event.storageId).json")
        let eventData = try jsonAdapter.encoder.encode(event)
        try eventData.write(to: eventFileURL)
    }

    // Loads all events of a given type
    func loadEvents(ofType eventType: String) async throws -> [AnyEventRepresentable] {
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
        return events
    }

    // Removes a specific event file
    func remove(ofType eventType: String, withStorageId storageId: String) async {
        let eventFileURL = baseDirectory.appendingPathComponent(eventType).appendingPathComponent("\(storageId).json")
        do {
            try fileManager.removeItem(at: eventFileURL)
        } catch {
            logger.error("Warning: Could not remove event file at \(eventFileURL). Error: \(error)")
        }
    }

    // Creates a directory if needed
    private func createDirectoryIfNeeded(_ directory: URL) async throws {
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
