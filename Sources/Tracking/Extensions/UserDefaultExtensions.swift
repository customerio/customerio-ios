import Foundation

internal extension UserDefaults {
    func deleteAll() {
        dictionaryRepresentation().keys.forEach { removeObject(forKey: $0) }
    }
}
