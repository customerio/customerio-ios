import Foundation

/// Represents the current state of the SSE connection.
/// Corresponds to Android's `SseConnectionState` enum.
///
/// Connection state transitions:
/// - DISCONNECTED -> CONNECTING (startConnection)
/// - CONNECTING -> CONNECTED (ConnectionOpenEvent/CONNECTED event from server)
/// - CONNECTED -> DISCONNECTING (stopConnection)
/// - CONNECTING/CONNECTED -> DISCONNECTED (ConnectionFailedEvent/ConnectionClosedEvent from SseService)
/// - DISCONNECTING -> DISCONNECTED (stopConnection completes)
enum SseConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case disconnecting

    var description: String {
        switch self {
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case .disconnecting:
            return "disconnecting"
        }
    }
}
