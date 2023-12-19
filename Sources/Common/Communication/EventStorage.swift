import Foundation

public protocol EventStorage: AutoMockable {
    /// Stores an event.
    func store(event: AnyEventRepresentable) throws
    /// Loads all events of a specific type.
    func loadEvents(ofType type: String) throws -> [AnyEventRepresentable]
    /// Removes a specific event by its storage identifier.
    func remove(ofType eventType: String, withStorageId storageId: String)
}

enum EventBusError: Error {
    case invalidEventType
    case decodingError
}

// sourcery: InjectRegisterShared = "EventStorage"
public class EventStorageManager: EventStorage {
    private let fileManager = FileManager.default
    public var baseDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let ioQueue: DispatchQueue

    init() {
        let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.baseDirectory = documentDirectory.appendingPathComponent("Events")
        self.ioQueue = DispatchQueue(label: "queue.eventstorage")
    }

    // for testing
    func updateBaseDirectory(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
    }

    /// Stores an event by creating a JSON file within a directory named after the event's type.
    /// The file is named using the event's unique storage identifier.
    public func store(event: AnyEventRepresentable) throws {
        try ioQueue.sync {
            let eventTypeDirectory = baseDirectory.appendingPathComponent(event.key)
            try createDirectoryIfNeeded(eventTypeDirectory)

            let eventFileURL = eventTypeDirectory.appendingPathComponent("\(event.storageId).json")
            let eventData = try encoder.encode(event)
            try eventData.write(to: eventFileURL)
        }
    }

    /// Loads all events of a given type by reading JSON files from a directory named after the event type.
    /// Each event is decoded from its respective file and returned in an array.
    public func loadEvents(ofType eventType: String) throws -> [AnyEventRepresentable] {
        try ioQueue.sync {
            let eventTypeDirectory = baseDirectory.appendingPathComponent(eventType)
            guard fileManager.fileExists(atPath: eventTypeDirectory.path) else { return [] }

            let fileURLs = try fileManager.contentsOfDirectory(at: eventTypeDirectory, includingPropertiesForKeys: nil)
            let eventTypeClass = try EventTypesRegistry.getEventType(for: eventType)

            var events: [AnyEventRepresentable] = []
            for url in fileURLs {
                let data = try Data(contentsOf: url)
                do {
                    let event = try decoder.decode(eventTypeClass, from: data)
                    events.append(event)
                } catch {
                    print("Warning: Could not decode event at \(url). Error: \(error)")
                }
            }
            return events
        }
    }

    /// Removes a specific event file based on its type and unique storage identifier.
    /// The file is located in the directory named after the event type and is identified by the storageId.
    public func remove(ofType eventType: String, withStorageId storageId: String) {
        ioQueue.sync {
            let eventFileURL = baseDirectory.appendingPathComponent(eventType).appendingPathComponent("\(storageId).json")
            do {
                try fileManager.removeItem(at: eventFileURL)
            } catch {
                print("Warning: Could not remove event file at \(eventFileURL). Error: \(error)")
            }
        }
    }

    /// Creates a directory at the specified URL if it does not already exist.
    /// This is used to create directories for event types as needed.
    private func createDirectoryIfNeeded(_ directory: URL) throws {
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
