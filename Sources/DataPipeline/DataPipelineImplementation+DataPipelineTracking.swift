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

// extension methods to simplify and reduce repetitive coding
extension DataPipelineImplementation {
    /// returns user id for currently identifier profile
    var registeredUserId: String? {
        analytics.userId
    }
}
