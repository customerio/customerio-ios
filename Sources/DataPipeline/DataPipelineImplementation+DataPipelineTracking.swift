import CioAnalytics

// MARK: - DataPipelineTracking

extension DataPipelineImplementation {
    var isUserIdentified: Bool {
        guard let userId = segment.userId, !userId.isEmpty else { return false }
        return true
    }

    func track(name: String, properties: [String: Any]) {
        // Another module's event, not the app's call
        DataPipelineLogTail.input("module.track", [("event", name)]) {
            segment.track(name: name, properties: properties)
        }
    }
}

// extension methods to simplify and reduce repetitive coding
extension DataPipelineImplementation {
    /// returns user id for currently identifier profile
    var registeredUserId: String? {
        segment.userId
    }
}
