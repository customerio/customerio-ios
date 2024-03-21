import CioTracking
import Foundation

struct WorkspaceSettings: UserDefaultsCodable {
    var cdpApiKy: String

    static func storageKey() -> String {
        "UserDefaultsCodable"
    }

    static func empty() -> Self {
        WorkspaceSettings(cdpApiKy: "")
    }

    func isSet() -> Bool {
        !cdpApiKy.isEmpty
    }
}

struct Profile: UserDefaultsCodable {
    var id: String
    var properties: [Property]
    var loggedIn: Bool

    static func empty() -> Profile {
        Profile(id: UUID().uuidString, properties: [], loggedIn: false)
    }

    static func storageKey() -> String {
        "Profile"
    }
}

struct Property: Codable, Identifiable, Comparable, Equatable {
    static func < (lhs: Property, rhs: Property) -> Bool {
        lhs.name == rhs.name
    }

    let id: String
    var name: String
    var value: String

    init(name: String, value: String) {
        self.id = UUID().uuidString
        self.name = name
        self.value = value
    }
}

extension [Property] {
    func toDictionary() -> [String: String] {
        var res: [String: String] = [:]
        forEach { p in
            if !p.name.isEmpty {
                res[p.name] = p.value
            }
        }
        return res
    }
}
