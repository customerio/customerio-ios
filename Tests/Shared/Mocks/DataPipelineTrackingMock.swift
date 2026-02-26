import CioInternalCommon
import Foundation

/// Mock of DataPipelineTracking for tests. Use when testing Location or any code that resolves pipeline via getOptional.
public final class DataPipelineTrackingMock: DataPipelineTracking {
    public var userId: String?

    public private(set) var trackCallsCount = 0
    public private(set) var trackInvocations: [(name: String, properties: [String: Any])] = []

    public init(userId: String? = "test-user-id") {
        self.userId = userId
    }

    public func track(name: String, properties: [String: Any]) {
        trackCallsCount += 1
        trackInvocations.append((name: name, properties: properties))
    }

    public func reset() {
        trackCallsCount = 0
        trackInvocations = []
    }
}
