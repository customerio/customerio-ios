@testable import CioLocation
import Foundation

/// In-memory implementation of LastLocationStateStore for tests.
final class InMemoryLastLocationStateStore: LastLocationStateStore {
    private var state: LastLocationState?

    init() {}

    func load() -> LastLocationState? {
        state
    }

    func save(_ state: LastLocationState) {
        self.state = state
    }
}
