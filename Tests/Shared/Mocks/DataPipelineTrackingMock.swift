import CioInternalCommon
import Foundation

/// Mock of DataPipelineTracking for tests. Use when testing Location or any code that resolves pipeline via getOptional.
public final class DataPipelineTrackingMock: DataPipelineTracking {
    public var isUserIdentified: Bool

    public private(set) var trackCallsCount = 0
    public private(set) var trackInvocations: [(name: String, properties: [String: Any])] = []

    public init(isUserIdentified: Bool = true) {
        self.isUserIdentified = isUserIdentified
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
