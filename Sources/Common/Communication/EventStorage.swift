import Foundation

protocol EventStorage: AutoMockable {
    func store<E: Codable>(
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(event)"
        event: E,
        forKey key: String
    ) throws
    func loadAllEvents(
        ofType type: any EventRepresentable.Type,
        withKey key: String
    ) throws -> [any EventRepresentable]
    func clearEvent(forKey key: String) throws
    func clearAllEvents() throws
}

// sourcery: InjectRegisterShared = "EventStorage"
class EventStorageManager: EventStorage {
    private let fileManager: FileManager = .default
    private let documentsDirectory: URL

    init() {
        self.documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    func store<E: Codable>(event: E, forKey key: String) throws {
        // Append a unique identifier (e.g., current timestamp) to the filename.
        let uniqueID = UUID().uuidString
        let filename = "\(key)_\(uniqueID).json"
        // put *all* files into our own "io.customer" directory to isolate files.
        var saveLocationUrl = documentsDirectory.appendingPathComponent("io.customer", isDirectory: true)

        // isolate all events
        saveLocationUrl = saveLocationUrl.appendingPathComponent("event-storage", isDirectory: true)

        let fileURL = saveLocationUrl.appendingPathComponent(filename, isDirectory: false)

        let data = try JSONEncoder().encode(event)
        try data.write(to: fileURL, options: [.atomicWrite])
    }

    func loadAllEvents(ofType type: any EventRepresentable.Type, withKey key: String) throws -> [any EventRepresentable] {
        try loadAllCodableEvents(ofType: type, withKey: key)
    }

    // Load all events of a specific type.
    func loadAllCodableEvents<E: Codable>(ofType type: E.Type, withKey key: String) throws -> [E] {
        let filePrefix = "\(key)_"
        let eventFiles = try listFiles(withPrefix: filePrefix)
        var events = [E]()

        for fileURL in eventFiles {
            let data = try Data(contentsOf: fileURL)
            let event = try JSONDecoder().decode(E.self, from: data)
            events.append(event)

            // Optionally, remove the file after loading
            try fileManager.removeItem(at: fileURL)
        }

        return events
    }

    // Helper method to list all files with a specific prefix.
    private func listFiles(withPrefix prefix: String) throws -> [URL] {
        let files = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
        return files.filter { $0.lastPathComponent.starts(with: prefix) }
    }

    func clearEvent(forKey key: String) throws {
        let filePrefix = "\(key)_"
        let eventFiles = try listFiles(withPrefix: filePrefix)

        for fileURL in eventFiles {
            try fileManager.removeItem(at: fileURL)
        }
    }

    func clearAllEvents() throws {
        let contents = try fileManager.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil)
        for fileURL in contents where fileURL.pathExtension == "json" {
            try fileManager.removeItem(at: fileURL)
        }
    }
}
