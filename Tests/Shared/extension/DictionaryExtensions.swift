extension Dictionary where Key == String, Value == Any {
    /// Flattens a nested dictionary into a single-level dictionary with unique keys.
    /// Nested dictionaries are merged into the root level, with their keys combined with parent keys using an underscore as a separator.
    ///
    /// - Parameters:
    ///   - parentKey: A string representing the key path leading to the current dictionary. This is primarily for internal use in recursive calls but can be specified to prepend a prefix to all keys in the flattened dictionary. Defaults to an empty string.
    /// - Returns: A single-level dictionary with combined keys and values from all levels of the original dictionary.
    ///
    /// # Example 1: Basic Usage
    /// ```
    /// let userProfile: [String: Any] = [
    ///     "name": "John Doe",
    ///     "age": 30,
    ///     "address": [
    ///         "street": "123 Main St",
    ///         "city": "Anytown",
    ///         "zip": "12345"
    ///     ]
    /// ]
    ///
    /// let flattenedProfile = userProfile.flatten()
    /// print(flattenedProfile)
    /// // Output:
    /// // [
    /// //     "name": "John Doe",
    /// //     "age": 30,
    /// //     "address_street": "123 Main St",
    /// //     "address_city": "Anytown",
    /// //     "address_zip": "12345"
    /// // ]
    /// ```
    ///
    /// # Example 2: Using `parentKey` to Prepend a Prefix
    /// ```
    /// let additionalInfo: [String: Any] = [
    ///     "hobbies": ["reading", "hiking"],
    ///     "profession": "Software Developer"
    /// ]
    ///
    /// // Using 'userDetails_' as a prefix to all keys
    /// let flattenedWithPrefix = additionalInfo.flatten(parentKey: "userDetails")
    /// print(flattenedWithPrefix)
    /// // Output:
    /// // [
    /// //     "userDetails_hobbies": ["reading", "hiking"],
    /// //     "userDetails_profession": "Software Developer"
    /// // ]
    /// ```
    func flatten(parentKey: String = "") -> [String: Any] {
        var flattened = [String: Any]()

        for (key, value) in self {
            let newKey = parentKey.isEmpty ? key : "\(parentKey)_\(key)"

            if let subDictionary = value as? [String: Any] {
                let flattenedSub = subDictionary.flatten(parentKey: newKey)
                for (subKey, subValue) in flattenedSub {
                    flattened[subKey] = subValue
                }
            } else {
                flattened[newKey] = value
            }
        }

        return flattened
    }
}
