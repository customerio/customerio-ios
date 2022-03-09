import Foundation

extension Dictionary where Key == String, Value == Any {
    public func mergeWith(_ other: [String: Any]) -> [String: Any] {
        return self.merging(other) { $1 }
    }
}
