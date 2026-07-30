import CioInternalCommon
import CioLiveActivities_Attributes
import Foundation

#if os(iOS)
import ActivityKit
#endif

/// How the first observed terminal ActivityKit state should be handled.
enum LiveActivityTerminalAction: Equatable {
    /// App/SDK/backend/system end — clean up local state, report nothing.
    case cleanupOnly
    /// User swiped the activity away — report an `end` event, then clean up.
    case reportUserDismiss
}

/// Pure decision for the terminal-state discriminator, factored out of ActivityKit observation so
/// it is unit-testable. A user dismissal is the case where the *first* terminal state observed is
/// `.dismissed` and the SDK did not end the activity itself.
func liveActivityTerminalAction(firstTerminalIsDismissed: Bool, wasLocalEnd: Bool) -> LiveActivityTerminalAction {
    (firstTerminalIsDismissed && !wasLocalEnd) ? .reportUserDismiss : .cleanupOnly
}

/// Owns the ActivityKit observation lifecycle for all registered activity types.
///
/// Starts one root task per registration, can `restart` after a reset, and cancels everything
/// on `stop`/`deinit`. Observation only *captures tokens* (routed to the registrar) and surfaces
/// appeared/ended signals — it never emits lifecycle events. Those come exclusively from the
/// `start`/`end` API via `LiveActivityReporter` (a local `update` applies content but is not
/// reported), so backend-initiated (push) changes are never echoed back.
final class LiveActivityObserver: @unchecked Sendable {
    private let registrations: [ActivityTypeRegistration]
    private let registrar: LiveActivityRegistrar
    private let localEndTracker: LiveActivityLocalEndTracker
    private let store: LiveActivityTokenStorage
    private let onUserDismissed: @Sendable (_ notificationType: String, _ cioInstanceId: String) -> Void
    private let onContentMetadata: @Sendable (_ notificationType: String, _ cioInstanceId: String, _ metadata: CIOLiveActivityMetadata) -> Void
    private let onActivityEnded: @Sendable (_ cioInstanceId: String) -> Void

    /// Running root tasks keyed by notificationType.
    private let tasks = Synchronized<[String: Task<Void, Never>]>([:])

    init(
        registrations: [ActivityTypeRegistration],
        registrar: LiveActivityRegistrar,
        localEndTracker: LiveActivityLocalEndTracker,
        store: LiveActivityTokenStorage,
        onUserDismissed: @escaping @Sendable (_ notificationType: String, _ cioInstanceId: String) -> Void,
        onContentMetadata: @escaping @Sendable (_ notificationType: String, _ cioInstanceId: String, _ metadata: CIOLiveActivityMetadata) -> Void,
        onActivityEnded: @escaping @Sendable (_ cioInstanceId: String) -> Void
    ) {
        self.registrations = registrations
        self.registrar = registrar
        self.localEndTracker = localEndTracker
        self.store = store
        self.onUserDismissed = onUserDismissed
        self.onContentMetadata = onContentMetadata
        self.onActivityEnded = onActivityEnded
    }

    func start() {
        for registration in registrations {
            startObserving(registration)
        }
    }

    /// Cancel and re-start all observation (used after a reset so a new session is observed).
    func restart() {
        stop()
        start()
    }

    func stop() {
        let running = tasks.wrappedValue
        for (_, task) in running {
            task.cancel()
        }
        tasks.wrappedValue = [:]
    }

    deinit {
        stop()
    }

    private func startObserving(_ registration: ActivityTypeRegistration) {
        let registrar = self.registrar
        let localEndTracker = self.localEndTracker
        let store = self.store
        let onUserDismissed = self.onUserDismissed
        let onContentMetadata = self.onContentMetadata
        let onActivityEnded = self.onActivityEnded
        let identifier = registration.activityIdentifier
        let attributesType = registration.attributesTypeName

        let sinks = LiveActivityObservationSinks(
            onPushToStartToken: { token in
                registrar.handlePushToStartToken(notificationType: identifier, attributesType: attributesType, token: token)
            },
            onInstanceToken: { instanceId, token in
                registrar.handleInstanceToken(notificationType: identifier, instanceUUID: instanceId, token: token)
            },
            onActivityEnded: { instanceId in
                registrar.handleActivityEnded(instanceUUID: instanceId)
                // Notify the module so it can evict any per-instance state (e.g. deep-link
                // metadata) — a terminated activity must not keep matching later opens.
                onActivityEnded(instanceId)
            },
            onUserDismissed: { instanceId in
                onUserDismissed(identifier, instanceId)
            },
            onContentMetadata: { instanceId, metadata in
                onContentMetadata(identifier, instanceId, metadata)
            },
            consumeLocalEnd: { instanceId in
                localEndTracker.consume(instanceId)
            },
            resolveInstanceId: { activityId, attributesInstanceId in
                store.resolveInstanceId(forActivityId: activityId) {
                    if let attributesInstanceId, !attributesInstanceId.isEmpty { return attributesInstanceId }
                    return ULID.generate()
                }
            },
            clearInstanceIdMapping: { activityId in
                store.clearInstanceId(forActivityId: activityId)
            }
        )

        tasks.mutating { existing in
            // Cancel any prior task for this type before replacing, so a repeated `start()`
            // (double init / re-entrancy) can't leave a second observer running in parallel.
            existing[identifier]?.cancel()
            existing[identifier] = registration.startObserving(sinks)
        }
    }
}

// MARK: - ActivityKit bridge

/// Builds the type-erased `ActivityTypeRegistration` for a concrete attributes type, keeping all
/// generic `Activity<T>` stream handling here rather than in the config builder.
enum LiveActivityObservation {
    #if os(iOS)
    /// Registration for a `CIOActivityAttribute` type: full observation **including push-to-start**.
    /// For a backend-created activity the instance id is read from its attributes (`cioInstanceId`).
    @available(iOS 16.2, *)
    static func registration<T: CIOActivityAttribute>(for type: T.Type, identifier: String) -> ActivityTypeRegistration {
        makeRegistration(for: T.self, identifier: identifier, observesPushToStart: true) { $0.attributes.cioInstanceId }
    }

    /// Registration for a plain `ActivityAttributes` type: instance-token, lifecycle and relaunch
    /// observation only — **no push-to-start** (the backend can't stamp an id into attributes the
    /// SDK can read), so the instance id is the SDK-minted one recovered from the persisted map.
    @available(iOS 16.2, *)
    static func registration<T: ActivityAttributes>(for type: T.Type, identifier: String) -> ActivityTypeRegistration {
        makeRegistration(for: T.self, identifier: identifier, observesPushToStart: false) { _ in nil }
    }

    /// Shared observation wiring for both registration flavors. `attributesInstanceId` extracts the
    /// id from an activity's attributes (conforming types) or returns `nil` (plain types); the
    /// resolved id then comes from the token store's persisted map, falling back to that value or a
    /// freshly minted ULID.
    @available(iOS 16.2, *)
    private static func makeRegistration<T: ActivityAttributes>(
        for type: T.Type,
        identifier: String,
        observesPushToStart: Bool,
        attributesInstanceId: @escaping @Sendable (Activity<T>) -> String?
    ) -> ActivityTypeRegistration {
        ActivityTypeRegistration(
            activityIdentifier: identifier,
            attributesTypeName: String(describing: T.self),
            startObserving: { sinks in
                Task {
                    await withTaskGroup(of: Void.self) { group in
                        if observesPushToStart {
                            group.addTask {
                                // Push-to-start is the only iOS 17.2 dependency. On 16.2–17.1 the SDK
                                // still observes instance-token updates, content/state changes, and
                                // local start/update/end — it just can't receive push-to-start tokens.
                                if #available(iOS 17.2, *) {
                                    for await token in Activity<T>.pushToStartTokenUpdates {
                                        sinks.onPushToStartToken(token)
                                    }
                                }
                            }
                        }
                        group.addTask {
                            // Observe each activity instance exactly once, deduped by the system
                            // `activity.id`, across BOTH sources:
                            //   1. `Activity.activities` — the current snapshot, which resumes
                            //      activities that started while the app was terminated (e.g.
                            //      push-to-start) or that survive a relaunch.
                            //   2. `activityUpdates` — activities started from now on.
                            // `activityUpdates` alone does not reliably replay already-running
                            // activities on a cold-launch subscription, so the snapshot is required
                            // to avoid missing their instance-token updates and end. The shared
                            // dedup set makes observing both sources safe.
                            let observedIds = Synchronized<Set<String>>([])
                            let claimUnobserved: @Sendable (String) -> Bool = { activityId in
                                observedIds.mutating { ids -> Bool in
                                    guard !ids.contains(activityId) else { return false }
                                    ids.insert(activityId)
                                    return true
                                }
                            }
                            await withTaskGroup(of: Void.self) { perActivity in
                                for activity in Activity<T>.activities where claimUnobserved(activity.id) {
                                    perActivity.addTask { await observe(activity, attributesInstanceId: attributesInstanceId(activity), sinks: sinks) }
                                }
                                for await activity in Activity<T>.activityUpdates where claimUnobserved(activity.id) {
                                    perActivity.addTask { await observe(activity, attributesInstanceId: attributesInstanceId(activity), sinks: sinks) }
                                }
                            }
                        }
                    }
                }
            },
            endAllActivities: { prepareLocalEnd in
                for activity in Activity<T>.activities {
                    // Mark as an SDK-initiated end first: the `.immediate` dismissal below surfaces
                    // as a `.dismissed` terminal, which the observer would otherwise report as a user
                    // swipe. On reset no `end` may fire (the user is being de-identified).
                    prepareLocalEnd(activity.id, attributesInstanceId(activity))
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        )
    }

    @available(iOS 16.2, *)
    private static func observe<T: ActivityAttributes>(_ activity: Activity<T>, attributesInstanceId: String?, sinks: LiveActivityObservationSinks) async {
        let instanceId = sinks.resolveInstanceId(activity.id, attributesInstanceId)
        // The initial content-state (from the start push) may carry Customer.io delivery metadata;
        // surface it so a push-to-start `delivered` receipt is reported and the tap destination is
        // recorded — even on a cold-launch snapshot where no `contentUpdates` will replay.
        if let metadata = (activity.content.state as? CIOMetadataCarrying)?.cioMetadata {
            sinks.onContentMetadata(instanceId, metadata)
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await token in activity.pushTokenUpdates {
                    sinks.onInstanceToken(instanceId, token)
                }
            }
            group.addTask {
                // Each backend push update carries its own delivery id in the content-state; surface
                // it for a per-update `delivered` receipt. (Runs only while the process is alive —
                // updates delivered to a killed app can't be observed and are dropped by design.)
                for await content in activity.contentUpdates {
                    if let metadata = (content.state as? CIOMetadataCarrying)?.cioMetadata {
                        sinks.onContentMetadata(instanceId, metadata)
                    }
                }
            }
            // Drive terminal detection here (not in a child task) so that on the first terminal we can
            // cancel the sibling token/content tasks immediately — otherwise a late instance-token
            // emission after teardown could re-register an instance the registrar just ended.
            //
            // The first terminal state observed distinguishes a user's manual dismissal from an
            // app/SDK/backend end:
            //   • `.ended` first  → the app (`CIOLiveActivity.end`), a backend push, or the system
            //                       ended it. Not a user swipe; clean up, report nothing (a local end
            //                       already reported via the handle; a backend end must not be echoed).
            //   • `.dismissed` first → the user swiped it away. Report `end` — unless it was a local
            //                       `end(.immediate)` whose `.ended` the stream coalesced (caught by
            //                       the local-end marker).
            for await state in activity.activityStateUpdates {
                let firstTerminalIsDismissed: Bool
                switch state {
                case .ended: firstTerminalIsDismissed = false
                case .dismissed: firstTerminalIsDismissed = true
                default: continue // not terminal — keep observing
                }
                let action = liveActivityTerminalAction(
                    firstTerminalIsDismissed: firstTerminalIsDismissed,
                    // Consume the marker on any terminal so a local end never leaks a marker
                    // and never double-reports.
                    wasLocalEnd: sinks.consumeLocalEnd(instanceId)
                )
                if action == .reportUserDismiss {
                    sinks.onUserDismissed(instanceId)
                }
                sinks.onActivityEnded(instanceId)
                sinks.clearInstanceIdMapping(activity.id)
                break
            }
            // Terminal reached (or the state stream ended): stop observing tokens/content for this
            // instance so nothing is routed to the registrar after teardown.
            group.cancelAll()
        }
    }
    #endif
}
