@testable import CioLocation
import Foundation
import UIKit

/// Stub for tests. Control app state so the lifecycle observer can be tested for "already active" vs "register for didBecomeActive".
/// Use `setApplicationState(_:)` to configure from test code (nonisolated); the protocol getter is MainActor-isolated.
final class StubApplicationStateProvider: ApplicationStateProvider {
    private var _state: UIApplication.State = .inactive

    @MainActor
    var applicationState: UIApplication.State { _state }

    /// Set from test code without MainActor isolation.
    func setApplicationState(_ state: UIApplication.State) {
        _state = state
    }
}
