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
        // Read the state AFTER the messages, in the same actor call: whatever store change the
        // message read observed is already reflected here, so the pair can never straddle versions.
        return (currentLoadState, messages)
    }

    func templatesRegistry() async -> InboxTemplatesRegistry? {
        cachedTemplates()
    }

    func branding() async -> InboxBranding? {
        cachedBranding()
    }
}
