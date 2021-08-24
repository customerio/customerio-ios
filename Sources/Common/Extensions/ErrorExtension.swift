import Foundation

public extension LocalizedError where Self: CustomStringConvertible {
    var errorDescription: String? {
        description
    }
}
