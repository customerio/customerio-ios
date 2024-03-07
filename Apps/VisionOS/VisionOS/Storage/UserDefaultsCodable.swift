import Foundation

protocol UserDefaultsCodable: Codable {
    static func storageKey() -> String
    static func empty() -> Self
}

extension UserDefaultsCodable {
    func toJson() -> Data {
        let encoder = JSONEncoder()
        return try! encoder.encode(self)
    }

    static func from(_ data: Data) -> Self? {
        let decoder = JSONDecoder()
        return try? decoder.decode(Self.self, from: data)
    }

    static func loadFromStorage() -> Self {
        if let data =
            UserDefaults.standard.object(forKey: storageKey()) as? Data,
            let storedInstance = from(data) {
            return storedInstance
        }

        let content = Self.empty()
        UserDefaults.standard.setValue(
            content.toJson(),
            forKey: Self.storageKey()
        )

        return content
    }
}
