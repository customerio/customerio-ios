import Foundation

/// Manages session-level identifiers that persist for the lifetime of the app launch
internal class SessionManager {
    static let shared = SessionManager()
    let sessionId: String

    private init() {
        self.sessionId = UUID().uuidString.lowercased()
    }
}
