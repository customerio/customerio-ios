import CioInternalCommon
import Foundation

// Store observation and session lifecycle for the visual-inbox data layer, split out of
// `VisualInboxRepository.swift` (the actor's core) to keep each file within the file-length limit.

extension VisualInboxRepositoryImpl {
    /// Clears the persisted render assets and reopens the revalidation gate when the user logs out.
    ///
    /// The assets and the enablement flag are workspace-scoped rather than per-user, so without this
    /// a logout would leave the next user rendering the previous one's inbox until the process
    /// restarted.
    func subscribeToLogout() {
        let subscriber = InAppMessageStoreSubscriber { [weak self] state in
            Task { [weak self] in
                await self?.handleUserChange(userId: state.userId)
            }
        }
        userSubscriber = subscriber
        inAppMessageManager.subscribe(keyPath: \.userId, subscriber: subscriber)
    }

    /// Reacts to a `userId` change. Only a transition away from a previously-known user clears:
    /// every cold launch starts with a nil `userId` before identify runs, and clearing on that
    /// would defeat the persisted cache entirely.
    func handleUserChange(userId: String?) {
        if let userId {
            lastKnownUserId = userId
            return
        }
        guard lastKnownUserId != nil else { return }
        lastKnownUserId = nil
        assetsCache.clear()
        didRevalidateThisSession = false
        currentLoadState = .hidden(reason: "inbox disabled")
        logger.logWithModuleTag("[CIO-Inbox] logout: cleared persisted render assets and reopened revalidation", level: .debug)
    }

    // MARK: - Message-change observation

    /// Subscribes to the in-app store's `inboxMessages` so the visual inbox stays in sync under the
    /// SSE path. Under SSE, messages arrive via `processInboxMessages` (a store update) without
    /// running the queue HTTP pipeline, so `runInboxPipeline` never recomputes `loadState`. We mirror
    /// `DefaultNotificationInbox`'s subscription and re-resolve `loadState` on each message change.
    ///
    /// Network-free: the recompute reuses the CURRENTLY-CACHED templates/branding + the enabled flag
    /// and the live message selection. It NEVER calls `performRevalidation`, and it respects the
    /// once-per-session gate (`didRevalidateThisSession`) so it cannot trigger a fetch.
    func subscribeToInboxMessageChanges() {
        let subscriber = InAppMessageStoreSubscriber { [weak self] _ in
            // Hop back onto the actor; recompute reads cached assets + the current enabled flag only.
            Task { [weak self] in
                await self?.recomputeLoadStateFromCurrentMessages()
            }
        }
        messagesSubscriber = subscriber
        inAppMessageManager.subscribe(keyPath: \.inboxMessages, subscriber: subscriber)
    }

    /// Lightweight, network-free `loadState` recompute triggered by an inbox-message change.
    ///
    /// Gated so it can never trigger a fetch and never overrides a disabled inbox:
    ///  - if the inbox is disabled → `.hidden`;
    ///  - if this session has not yet revalidated → no-op (the pending `enableAndLoad` owns the first
    ///    resolution; recomputing here with possibly-empty cache would be premature);
    ///  - otherwise re-resolve from the currently-cached templates/branding + live messages.
    func recomputeLoadStateFromCurrentMessages() async {
        guard assetsCache.enabledFlag() ?? false else {
            currentLoadState = .hidden(reason: "inbox disabled")
            return
        }
        guard didRevalidateThisSession else { return }
        logger.logWithModuleTag("[CIO-Inbox] inbox messages changed → recomputing loadState (no fetch)", level: .debug)
        await resolveLoadState(templates: cachedTemplates(), branding: cachedBranding())
    }
}
