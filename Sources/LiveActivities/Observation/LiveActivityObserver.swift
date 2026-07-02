import CioInternalCommon
import CioLiveActivities_Attributes
import Foundation

#if os(iOS)
import ActivityKit
#endif

/// Owns the ActivityKit observation lifecycle for all registered activity types.
///
/// Starts one root task per registration, can `restart` after a reset, and cancels everything
/// on `stop`/`deinit`. Observation only *captures tokens* (routed to the registrar) and surfaces
/// appeared/ended signals — it never emits lifecycle events. Those come exclusively from the
/// `start`/`update`/`end` API via `LiveActivityReporter`, so backend-initiated (push) changes
/// are never echoed back.
final class LiveActivityObserver: @unchecked Sendable {
    private let registrations: [ActivityTypeRegistration]
    private let registrar: LiveActivityRegistrar
    private let onActivityAppeared: @Sendable (_ notificationType: String, _ activityInstanceId: String) -> Void

    /// Running root tasks keyed by notificationType.
    private let tasks = Synchronized<[String: Task<Void, Never>]>([:])

    init(
        registrations: [ActivityTypeRegistration],
        registrar: LiveActivityRegistrar,
        onActivityAppeared: @escaping @Sendable (_ notificationType: String, _ activityInstanceId: String) -> Void
    ) {
        self.registrations = registrations
        self.registrar = registrar
        self.onActivityAppeared = onActivityAppeared
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
        let onAppeared = onActivityAppeared
        let identifier = registration.activityIdentifier
        let attributesType = registration.attributesTypeName

        let sinks = LiveActivityObservationSinks(
            onPushToStartToken: { token in
                registrar.handlePushToStartToken(notificationType: identifier, attributesType: attributesType, token: token)
            },
            onInstanceToken: { instanceId, token in
                registrar.handleInstanceToken(notificationType: identifier, instanceUUID: instanceId, token: token)
            },
            onActivityAppeared: { instanceId in
                onAppeared(identifier, instanceId)
            },
            onActivityEnded: { instanceId in
                registrar.handleActivityEnded(instanceUUID: instanceId)
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
    @available(iOS 17.2, *)
    static func registration<T: CIOActivityAttribute>(for type: T.Type, identifier: String) -> ActivityTypeRegistration {
        ActivityTypeRegistration(
            activityIdentifier: identifier,
            attributesTypeName: String(describing: T.self),
            startObserving: { sinks in
                Task {
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask {
                            for await token in Activity<T>.pushToStartTokenUpdates {
                                sinks.onPushToStartToken(token)
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
                                    perActivity.addTask { await observe(activity, sinks: sinks) }
                                }
                                for await activity in Activity<T>.activityUpdates where claimUnobserved(activity.id) {
                                    perActivity.addTask { await observe(activity, sinks: sinks) }
                                }
                            }
                        }
                    }
                }
            },
            endAllActivities: {
                for activity in Activity<T>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        )
    }

    @available(iOS 17.2, *)
    private static func observe<T: CIOActivityAttribute>(_ activity: Activity<T>, sinks: LiveActivityObservationSinks) async {
        let instanceId = activity.attributes.activityInstanceId
        sinks.onActivityAppeared(instanceId)
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await token in activity.pushTokenUpdates {
                    sinks.onInstanceToken(instanceId, token)
                }
            }
            group.addTask {
                for await state in activity.activityStateUpdates {
                    switch state {
                    case .ended, .dismissed:
                        sinks.onActivityEnded(instanceId)
                        return
                    default:
                        break
                    }
                }
            }
        }
    }
    #endif
}
