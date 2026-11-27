import CioAnalytics

// MARK: - Deprecated properties

extension DataPipelineImplementation {
    @available(*, deprecated, message: "Use setProfileAttributes() instead")
    var profileAttributes: [String: Any] {
        get { analytics.traits() ?? [:] }
        set { setProfileAttributes(newValue) }
    }

    @available(*, deprecated, message: "Use setDeviceAttributes method instead. This property getter always returns an empty dictionary.")
    var deviceAttributes: [String: Any] {
        get { [:] }
        set {
            setDeviceAttributes(newValue)
        }
    }
}
