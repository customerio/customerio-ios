import Foundation

import CioInternalCommon

extension Region: CaseIterable, Codable {
    public static var allCases: [Region] = [.EU, .US]
}

struct WorkspaceSettings: UserDefaultsCodable {
    var cdpApiKy: String
    var region: Region = .EU

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
