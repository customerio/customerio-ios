import Foundation

extension Dictionary where Key == String, Value == String {
    public func mergeWith(_ other: [String: String]) -> [String: String] {
        return self.merging(other) { $1 }
    }
}
