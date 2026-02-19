import Foundation

/// Reserved names and attribute keys used to enforce location guardrails.
/// Prevents consumers from bypassing the Location module by sending track events
/// or profile attributes that represent location.
enum DataPipelineReservedNames {
    /// Event name reserved for the SDK's internal location flow. Only the Location module
    /// should send this event (via TrackLocationEvent). Public track calls with this name are no-op'd.
    static let reservedLocationTrackEventName = "Location Update"

    /// Profile and track property keys that represent location. These are stripped from
    /// identify/setProfileAttributes and from track event properties so location can only
    /// be set via CustomerIO.location.
    static let reservedLocationAttributeKeys: Set<String> = [
        "location_latitude",
        "location_longitude"
    ]
}

/// Removes reserved location attribute keys from a dictionary. Other attributes are unchanged.
/// Use for both profile traits (identify/setProfileAttributes) and track event properties.
/// - Parameter attributes: The attributes to filter.
/// - Returns: A new dictionary with only `location_latitude` and `location_longitude` removed; all other keys preserved. Still send the update with the remaining attributes.
func attributesByRemovingReservedLocationKeys(_ attributes: [String: Any]) -> [String: Any] {
    guard !attributes.isEmpty else { return attributes }
    let keys = DataPipelineReservedNames.reservedLocationAttributeKeys
    return attributes.filter { !keys.contains($0.key) }
}

/// Returns true if the event name is reserved for the SDK's internal location flow (caller should no-op track).
func isReservedTrackEventName(_ name: String) -> Bool {
    name == DataPipelineReservedNames.reservedLocationTrackEventName
}

/// For public track calls: returns whether to send the event and the properties to use (reserved name → don't send; otherwise → filtered properties).
/// Caller should no-op when shouldSend is false and call analytics.track(name: properties:) when true.
func filterTrackParameters(name: String, properties: [String: Any]?) -> (shouldSend: Bool, properties: [String: Any]?) {
    guard !isReservedTrackEventName(name) else { return (false, nil) }
    let filtered = properties.map { attributesByRemovingReservedLocationKeys($0) }
    return (true, filtered?.nilIfEmpty)
}

/// Returns the properties that should be sent for a Codable (track/identify), with reserved location keys removed.
/// - Returns: Nil means use the original Codable (conversion failed or no reserved keys present). Non-nil means use this filtered dictionary.
func codableToDictRemovingReservedLocationKeys<T: Encodable>(_ value: T) -> [String: Any]? {
    let data: Data?
    do {
        data = try JSONEncoder().encode(value)
    } catch {
        return nil
    }
    guard let data = data,
          let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
        return nil
    }
    let keys = DataPipelineReservedNames.reservedLocationAttributeKeys
    let hadReservedKeys = !Set(dict.keys).isDisjoint(with: keys)
    guard hadReservedKeys else { return nil }
    return attributesByRemovingReservedLocationKeys(dict)
}
