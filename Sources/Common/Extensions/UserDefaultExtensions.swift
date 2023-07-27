import Foundation

internal extension UserDefaults {
    func deleteAll() {
        dictionaryRepresentation().keys.forEach { removeObject(forKey: $0) }
    }

    func copyValuesFrom(source: UserDefaults) {
        for key in source.dictionaryRepresentation().keys {
            if let value = source.value(forKey: key) {
                setValue(value, forKey: key)
            }
        }
    }
}
