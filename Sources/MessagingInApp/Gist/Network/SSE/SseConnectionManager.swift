import CioInternalCommon
import Foundation

// sourcery: InjectRegisterShared = "SseConnectionManager"
// sourcery: InjectSingleton
/// Manages SSE (Server-Sent Events) connections for real-time in-app message delivery.
/// This class handles connection lifecycle, event parsing, heartbeat monitoring, and automatic reconnection.
actor SseConnectionManager {
    private let logger: Logger
    private let inAppMessageManager: InAppMessageManager

    init(
        logger: Logger,
        inAppMessageManager: InAppMessageManager
    ) {
        self.logger = logger
        self.inAppMessageManager = inAppMessageManager
        logger.logWithModuleTag("SseConnectionManager initialized", level: .debug)
    }

    /// Starts an SSE connection to the queue consumer API.
    /// This method is idempotent - calling it multiple times while connected is safe.
    func startConnection(state: InAppMessageState) {
        logger.logWithModuleTag("SSE startConnection called", level: .info)

        logger.logWithModuleTag("  - useSse: \(state.useSse)", level: .debug)
        logger.logWithModuleTag("  - userId: \(state.userId ?? "nil")", level: .debug)
        logger.logWithModuleTag("  - anonymousId: \(state.anonymousId ?? "nil")", level: .debug)
        logger.logWithModuleTag("  - environment: \(state.environment)", level: .debug)

        // TODO: Phase 2 - Implement actual SSE connection logic
        logger.logWithModuleTag("SSE connection logic not yet implemented (Phase 2)", level: .debug)
    }

    /// Stops the active SSE connection.
    /// This method is idempotent - calling it multiple times is safe.
    func stopConnection() {
        logger.logWithModuleTag("SSE stopConnection called", level: .info)

        // TODO: Phase 2 - Implement connection cleanup logic
        logger.logWithModuleTag("SSE cleanup logic not yet implemented (Phase 2)", level: .debug)
    }
}
