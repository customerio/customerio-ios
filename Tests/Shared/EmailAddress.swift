@testable import CioTracking
import Foundation

public typealias EmailAddress = String

public extension EmailAddress {
    static var randomEmail: String {
        "\(String.random)@customer.io"
    }
}
