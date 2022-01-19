import Foundation

extension Array {
    mutating func removeFirstOrNil() -> Element? {
        guard !isEmpty else {
            return nil
        }

        return removeFirst()
    }
}
