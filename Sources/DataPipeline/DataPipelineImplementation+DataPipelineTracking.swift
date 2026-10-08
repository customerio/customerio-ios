import CioAnalytics

// MARK: - DataPipelineTracking

extension DataPipelineImplementation {
    var isUserIdentified: Bool {
        guard let userId = analytics.userId, !userId.isEmpty else { return false }
        return true
    }

    func track(name: String, properties: [String: Any]) {
        analytics.track(name: name, properties: properties)
    }
}
