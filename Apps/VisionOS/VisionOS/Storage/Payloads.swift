import CioTracking
import Foundation

extension Region: CaseIterable, Codable {
    public static var allCases: [Region] = [.EU, .US]
}

struct WorkspaceSettings: UserDefaultsCodable {
    var siteId: String
    var apiKey: String
    var region: Region = .EU

    static func storageKey() -> String {
        "UserDefaultsCodable"
    }

    static func empty() -> Self {
        WorkspaceSettings(siteId: "", apiKey: "")
    }

    func isSet() -> Bool {
        !siteId.isEmpty && !apiKey.isEmpty
    }
}

struct Profile: UserDefaultsCodable {
    var id: String
    var name: String
    var email: String
    var loggedIn: Bool

    static func empty() -> Profile {
        Profile(id: UUID().uuidString, name: "", email: "", loggedIn: false)
    }

    static func storageKey() -> String {
        "Profile"
    }
}

struct Event {
    var name: String = ""
    var propertyName: String = ""
    var propertyValue: String = ""
}

struct ProfileAttribute {
    var name: String
    var value: String
}

struct DeviceAttribute {
    var name: String
    var value: String
}

extension Profile {
    func fieldsToDictionay() -> [String: String] {
        var dic: [String: String] = [:]
        if !name.isEmpty {
            dic["name"] = name
        }

        if !email.isEmpty {
            dic["email"] = email
        }

        return dic
    }
}

extension Event {
    func fieldsToDictionay() -> [String: String] {
        var dic: [String: String] = [:]
        if !name.isEmpty {
            dic["name"] = name
        }

        if !propertyName.isEmpty {
            dic[propertyName] = propertyValue
        }

        return dic
    }
}
