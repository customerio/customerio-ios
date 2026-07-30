import CioInternalCommon
import Foundation

// The visual-inbox data layer's read surface, split out of `VisualInboxRepository.swift` (the actor's
// core) to keep each file within the file-length limit.

extension VisualInboxRepositoryImpl {
    func selectedMessages() async -> [InboxMessage] {
        // Read messages live from the headless source and apply visual-inbox selection on read.
        // Serve-stale is provided by the headless layer (a failed poll keeps the last-known-good set).
        let state = await inAppMessageManager.state
        let selected = VisualInboxSelector.select(messages: state.inboxMessages, now: currentDate())
        logger.logWithModuleTag(
            "[CIO-Inbox] selection: \(state.inboxMessages.count) state message(s) → \(selected.count) selected (cio_inbox prefix / priority / expiry)",
            level: .debug
        )
        return selected
    }

    func jistMessages() async -> [JistInboxMessage] {
        let selected = await selectedMessages()
        return InboxMessageJistAdapter.toJist(selected)
    }

    func loadStateAndJistMessages() async -> (state: VisualInboxLoadState, messages: [JistInboxMessage]) {
        let messages = await jistMessages()
        // One call instead of two narrows the window in which the pair can disagree, but does not
        // close it: `jistMessages()` awaits the store, and the store subscriber can recompute
        // `currentLoadState` from a newer update while this actor is suspended there. The returned
        // messages are internally consistent (one array, one selection); the state is best-effort and
        // may be a version ahead. The UI treats it as a visibility hint, so a transient disagreement
        // resolves on the next emission.
        return (currentLoadState, messages)
    }

    func templatesRegistry() async -> InboxTemplatesRegistry? {
        cachedTemplates()
    }

    func branding() async -> InboxBranding? {
        cachedBranding()
    }
}
