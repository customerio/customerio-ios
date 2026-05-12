public protocol DictionaryProtocol {
    associatedtype Key: Hashable
    associatedtype Value

    subscript(key: Key) -> Value? { get set }
    mutating func removeValue(forKey key: Key) -> Value?
}

extension Dictionary: DictionaryProtocol {}

extension Synchronized: DictionaryProtocol where T: DictionaryProtocol {
    public typealias Key = T.Key
    public typealias Value = T.Value

    /// Accesses the value associated with `key` in a thread-safe manner.
    ///
    /// - Warning: The getter and setter each acquire the lock independently.
    ///   Chained compound mutations such as `sync["key"]?.property = value` are
    ///   **not** atomic — use `mutating { $0["key"]?.property = value }` instead.
    public subscript(key: Key) -> Value? {
        get {
            using { value in
                value[key]
            }
        }
        set {
            mutating { value in
                value[key] = newValue
            }
        }
    }

    @discardableResult
    public func removeValue(forKey key: Key) -> Value? {
        var result: Value?
        mutating { value in
            result = value.removeValue(forKey: key)
        }
        return result
    }
}
