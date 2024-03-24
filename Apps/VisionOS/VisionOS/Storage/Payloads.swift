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
    var userId: String
    var traits: [Property]
    var loggedIn: Bool

    static func empty() -> Profile {
        Profile(userId: "", traits: [], loggedIn: false)
    }

    static func storageKey() -> String {
        "Profile"
    }
}

struct Property: Codable, Identifiable, Comparable, Equatable {
    static func < (lhs: Property, rhs: Property) -> Bool {
        lhs.key == rhs.key
    }

    var id: String {
        key
    }

    var key: String
    var value: String

    init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

extension [Property] {
    func toDictionary() -> [String: String] {
        var res: [String: String] = [:]
        forEach { p in
            if !p.key.isEmpty {
                res[p.key] = p.value
            }
        }
        return res
    }
}

typealias Attribute = Property

struct Event: Codable {
    var name: String
    var properties: [Property] = []
}
