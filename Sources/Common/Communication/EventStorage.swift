import Foundation

public protocol EventStorage {
    func store<E: Codable>(
        // sourcery:Type=AnyEncodable
        // sourcery:TypeCast="AnyEncodable(event)"
        event: E,
        forKey key: String
    ) throws
    func loadAllEvents<E: EventRepresentable & Codable>(
        ofType type: E.Type,
        withKey key: String
    ) throws -> [E]
    func remove(forKey key: String) throws
    func clearAllEvents() throws
}

// sourcery: InjectRegisterShared = "EventStorage"
public class EventStorageManager: EventStorage {
    private let userDefaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(userDefaults: UserDefaults = .standard) {
        // Creating a dedicated UserDefaults suite for events
        guard let eventUserDefaults = UserDefaults(suiteName: "eventbus.eventstorage") else {
            fatalError("Unable to create a UserDefaults suite for events")
        }
        self.userDefaults = eventUserDefaults
    }

    public func store<E: Codable>(event: E, forKey key: String) throws {
        do {
            let data = try encoder.encode(event)
            var eventsData = [Data]()
            if let existingData = userDefaults.array(forKey: key) as? [Data] {
                eventsData = existingData
            }
            eventsData.append(data)
            userDefaults.set(eventsData, forKey: key)
        } catch {
            print("Failed to store event: \(error)")
        }
    }

    // Load all events of a specific type.
    public func loadAllEvents<E: Codable>(ofType type: E.Type, withKey key: String) throws -> [E] {
        guard let eventsData = userDefaults.array(forKey: key) as? [Data] else {
            return []
        }

        return eventsData.compactMap { data in
            try? decoder.decode(E.self, from: data)
        }
    }

    public func remove(forKey key: String) throws {
        userDefaults.removeObject(forKey: key)
    }

    public func clearAllEvents() throws {
        userDefaults.deleteAll()
    }
}
