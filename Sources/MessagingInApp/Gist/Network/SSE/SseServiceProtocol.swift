import CioInternalCommon
import Foundation

/// Protocol for SSE service to enable testing with mocks.
/// Abstracts the SSE connection functionality so `SseConnectionManager` can be tested
/// without depending on the actual LDSwiftEventSource library.
///
/// Methods are marked `async` to support actor conformance (`SseService` is an actor).
/// This ensures proper actor isolation and prevents data races.
protocol SseServiceProtocol: AutoMockable {
    /// Starts SSE connection using the provided state and connection ID.
    /// The connection ID is provided by the manager to ensure both layers share the same identifier.
    /// - Parameters:
    ///   - state: The current InAppMessageState containing user and environment info
    ///   - connectionId: The connection ID from the manager, used to coordinate disconnect operations
    /// - Returns: AsyncStream of SSE events
    func connect(state: InAppMessageState, connectionId: UInt64) async -> AsyncStream<SseEvent>

    /// Stops the SSE connection only if the connection ID matches.
    /// This prevents race conditions where cleanup could kill a newer connection.
    /// - Parameter connectionId: The connection ID to disconnect
    func disconnect(connectionId: UInt64) async
}
