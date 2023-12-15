import Foundation

public protocol EventStorage {
    /// Stores an event.
    func store<E: EventRepresentable & Codable>(event: E) throws
    /// Loads all events of a specific type.
    func loadEvents<E: EventRepresentable & Codable>(ofType type: E.Type) throws -> [E]
    /// Removes a specific event by its storage identifier.
    func remove<E: EventRepresentable>(ofType eventType: E, withStorageId storageId: String) throws
}

// sourcery: InjectRegisterShared = "EventStorage"
public class EventStorageManager: EventStorage {
    private let fileManager = FileManager.default
    private let baseDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let ioQueue: DispatchQueue

    init() {
        let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.baseDirectory = documentDirectory.appendingPathComponent("Events")
        self.ioQueue = DispatchQueue(label: "queue.eventstorage")
    }

    /// Stores an event by creating a JSON file within a directory named after the event's type.
    /// The file is named using the event's unique storage identifier.
    public func store<E: Codable & EventRepresentable>(event: E) throws {
        try ioQueue.sync {
            let eventTypeDirectory = baseDirectory.appendingPathComponent(E.key)
            try createDirectoryIfNeeded(eventTypeDirectory)

            let eventFileURL = eventTypeDirectory.appendingPathComponent("\(event.storageId).json")
            let eventData = try encoder.encode(event)
            try eventData.write(to: eventFileURL)
        }
    }

    /// Loads all events of a given type by reading JSON files from a directory named after the event type.
    /// Each event is decoded from its respective file and returned in an array.
    public func loadEvents<E: Codable & EventRepresentable>(ofType eventType: E.Type) throws -> [E] {
        try ioQueue.sync {
            let eventTypeDirectory = baseDirectory.appendingPathComponent(E.key)
            guard fileManager.fileExists(atPath: eventTypeDirectory.path) else { return [] }

            let fileURLs = try fileManager.contentsOfDirectory(at: eventTypeDirectory, includingPropertiesForKeys: nil)
            return try fileURLs.compactMap { url in
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode(E.self, from: data)
            }
        }
    }

    /// Removes a specific event file based on its type and unique storage identifier.
    /// The file is located in the directory named after the event type and is identified by the storageId.
    public func remove<E: EventRepresentable>(ofType eventType: E, withStorageId storageId: String) throws {
        try ioQueue.sync {
            let eventFileURL = baseDirectory.appendingPathComponent(E.key).appendingPathComponent("\(storageId).json")
            try fileManager.removeItem(at: eventFileURL)
        }
    }

    /// Creates a directory at the specified URL if it does not already exist.
    /// This is used to create directories for event types as needed.
    private func createDirectoryIfNeeded(_ directory: URL) throws {
        guard !fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
