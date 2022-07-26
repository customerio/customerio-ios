@testable import CioTracking
import Foundation

/// Example request body object for identifying customer
public struct IdentifyRequestBody: Codable, Equatable {
    var email: String?
    /// test nested data
    var name: Name
    var update: Bool

    struct Name: Codable, Equatable {
        var firstName: String
        var lastName: String
    }

    /// Provide custom keys for JSON.
    /// Learn more: https://stackoverflow.com/a/45032910
    private enum CodingKeys: String, CodingKey {
        case email
        case name
        case update = "_update"
    }
}

public extension IdentifyRequestBody {
    static func random(update: Bool = false) -> IdentifyRequestBody {
        IdentifyRequestBody(
            email: EmailAddress.randomEmail,
            name: IdentifyRequestBody.Name(firstName: String.random, lastName: String.random),
            update: update
        )
    }
}
