@testable import CioMessagingInApp
import Foundation

/// Minimal `VisualInboxRepository` stand-in recording the calls the queue pipeline makes.
/// Hand-rolled because the protocol's `async` members are not expressible by the mock template.
actor VisualInboxRepositoryFake: VisualInboxRepository {
    private(set) var enableAndLoadCallCount = 0
    private(set) var setEnabledValues: [Bool] = []
    private var enabled = false

    var isInboxEnabled: Bool { enabled }
    var loadState: VisualInboxLoadState { .idle }
    var isInboxVisible: Bool { false }

    func enableAndLoad() async {
        enableAndLoadCallCount += 1
    }

    func selectedMessages() async -> [InboxMessage] {
        []
    }

    func jistMessages() async -> [JistInboxMessage] {
        []
    }

    func loadStateAndJistMessages() async -> (state: VisualInboxLoadState, messages: [JistInboxMessage]) {
        (.idle, [])
    }

    func templatesRegistry() async -> InboxTemplatesRegistry? {
        nil
    }

    func branding() async -> InboxBranding? {
        nil
    }

    @discardableResult
    func setInboxEnabled(_ enabled: Bool) async -> Bool {
        let previous = self.enabled
        self.enabled = enabled
        setEnabledValues.append(enabled)
        return previous
    }

    func loadStateChanges() async -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}
