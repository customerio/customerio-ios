import CioInternalCommon

extension DeviceTokenType {
    /// Reserved device attribute the backend lifts out to store the token type.
    static let attributeKey = "cio_token_type"
}

extension Dictionary where Key == String, Value == Any {
    /// Sets the reserved token type attribute to the SDK's type, or leaves it out when the type is unknown.
    /// Only the SDK sets it, so a value the app passed is dropped.
    func withDeviceTokenType(_ tokenType: DeviceTokenType?, logger: DataPipelinesLogger) -> [String: Any] {
        var attributes = self
        if attributes.removeValue(forKey: DeviceTokenType.attributeKey) != nil {
            logger.logReservedDeviceTokenTypeIgnored()
        }
        if let tokenType = tokenType {
            attributes[DeviceTokenType.attributeKey] = tokenType.rawValue
        }
        return attributes
    }
}
