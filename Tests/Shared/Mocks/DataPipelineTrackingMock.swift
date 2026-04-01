import CioInternalCommon
import Foundation

/// Mock of DataPipelineTracking for tests. Use when testing Location or any code that resolves pipeline via getOptional.
public final class DataPipelineTrackingMock: DataPipelineTracking {
    public struct DeliveryEventInvocation {
        public let token: String?
        public let event: String
        public let deliveryId: String
        public let timestamp: String
    }

    public var isUserIdentified: Bool

    public private(set) var trackCallsCount = 0
    public private(set) var trackInvocations: [(name: String, properties: [String: Any])] = []

    public private(set) var trackDeliveryEventCallsCount = 0
    public private(set) var trackDeliveryEventInvocations: [DeliveryEventInvocation] = []

    public init(isUserIdentified: Bool = true) {
        self.isUserIdentified = isUserIdentified
    }

    public func track(name: String, properties: [String: Any]) {
        trackCallsCount += 1
        trackInvocations.append((name: name, properties: properties))
    }

    public func trackDeliveryEvent(token: String?, event: String, deliveryId: String, timestamp: String) {
        trackDeliveryEventCallsCount += 1
        trackDeliveryEventInvocations.append(DeliveryEventInvocation(token: token, event: event, deliveryId: deliveryId, timestamp: timestamp))
    }

    public func reset() {
        trackCallsCount = 0
        trackInvocations = []
        trackDeliveryEventCallsCount = 0
        trackDeliveryEventInvocations = []
    }
}
