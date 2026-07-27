import CioInternalCommon
import Foundation

// Store observation and session lifecycle for the visual-inbox data layer, split out of
// `VisualInboxRepository.swift` (the actor's core) to keep each file within the file-length limit.

extension VisualInboxRepositoryImpl {
    /// Subscribes to the two store fields the visual inbox reacts to, through a SINGLE subscriber.
    ///
    /// `inboxMessages`: under SSE, messages arrive via `processInboxMessages` (a store update)
    /// without running the queue HTTP pipeline, so `runInboxPipeline` never recomputes `loadState`.
    /// `userId`: a logout must drop the workspace-scoped render assets before the next user.
    ///
    /// Deliberately one subscription rather than one per field: the repository is a DI singleton, so
    /// every extra subscriber adds a notification and an actor hop to every store mutation for the
    /// life of the process.
    ///
    /// Network-free: the recompute reuses the CURRENTLY-CACHED templates/branding + the enabled flag
    /// and the live message selection. It NEVER calls `performRevalidation`, and it respects the
    /// once-per-session gate (`didRevalidateThisSession`) so it cannot trigger a fetch.
    func subscribeToStoreChanges() {
        let subscriber = InAppMessageStoreSubscriber { [weak self] state in
            // Hop back onto the actor; the handlers read cached assets + the current enabled flag only.
            Task { [weak self] in
                await self?.handleStoreChange(state: state)
            }
        }
        storeSubscriber = subscriber
        inAppMessageManager.subscribe(
            comparator: { old, new in
                old.inboxMessages == new.inboxMessages && old.userId == new.userId
            },
            subscriber: subscriber
        )
    }

    private func handleStoreChange(state: InAppMessageState) async {
        // A logout already resolves `loadState` and wipes the cache, so there is nothing left to
        // recompute from.
        if handleUserChange(userId: state.userId) { return }
        await recomputeLoadStateFromCurrentMessages()
    }

    /// Reacts to a `userId` change, returning whether this was a logout that reset state.
    ///
    /// Only a transition away from a previously-known user clears: every cold launch starts with a
    /// nil `userId` before identify runs, and clearing on that would defeat the persisted cache.
    @discardableResult
    func handleUserChange(userId: String?) -> Bool {
        if let userId {
            lastKnownUserId = userId
            return false
        }
        guard lastKnownUserId != nil else { return false }
        lastKnownUserId = nil
        assetsCache.clear()
        didRevalidateThisSession = false
        currentLoadState = .hidden(reason: "inbox disabled")
        logger.logWithModuleTag("[CIO-Inbox] logout: cleared persisted render assets and reopened revalidation", level: .debug)
        return true
    }

    /// Lightweight, network-free `loadState` recompute triggered by a store change.
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
        logger.logWithModuleTag("[CIO-Inbox] store changed → recomputing loadState (no fetch)", level: .debug)
        await resolveLoadState(templates: cachedTemplates(), branding: cachedBranding())
    }
}
