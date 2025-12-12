import Foundation

/// Represents the current state of the SSE connection
enum SseConnectionState: Equatable {
    case disconnected
    case connecting
    case connected

    var description: String {
        switch self {
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        }
    }
}
