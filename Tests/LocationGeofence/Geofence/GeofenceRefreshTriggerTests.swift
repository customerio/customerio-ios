@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import Foundation
import SharedTests
import Testing

/// Bound for every wait for something to happen.
///
/// `settle`'s 2 s default is too short on CI, where suites run in parallel and these decisions
/// reach the main actor under contention. A late refresh can then land after the mock is reset.
/// A passing wait returns as soon as the condition holds, so this only delays a genuine failure.
private let waitForDetachedWork: TimeInterval = 10

/// Window for every assertion that something does *not* happen.
///
/// A negative can only be given long enough that the forbidden thing would have happened.
/// `settleQuietly`'s 0.3 s default is far shorter than the contention above. Paid on every green run.
private let windowForAbsence: TimeInterval = 2

/// Nested under `SharedDIGraphSuites` because `GeofenceStorage.init` defaults its `dateUtil` to
/// `DIGraphShared.shared.dateUtil`, so every `Harness` reads the shared graph.
extension SharedDIGraphSuites {
    @Suite("GeofenceRefreshTrigger")
    struct GeofenceRefreshTriggerTests {
        private final class Harness {
            let coordinator = GeofenceSyncCoordinatorMock()
            let contextStore: BackgroundDeliveryContextStore
            let storage: GeofenceStorage
            let explicitRefreshRequested = Synchronized<Bool>(false)

            /// Read from the trigger's decision task and written from the test, so synchronized.
            private let lastKnownBox = Synchronized<LocationData?>(nil)
            var lastKnown: LocationData? {
                get { lastKnownBox.wrappedValue }
                set { lastKnownBox.wrappedValue = newValue }
            }

            /// Runs when the decision reads `lastKnownLocation`, the one point a test can interpose
            /// on to land a reset mid-decision.
            private let onLastKnownReadBox = Synchronized<(() -> Void)?>(nil)
            var onLastKnownRead: (() -> Void)? {
                get { onLastKnownReadBox.wrappedValue }
                set { onLastKnownReadBox.wrappedValue = newValue }
            }

            private let root: URL

            /// Written from the decision task and polled from the test, so synchronized.
            private let acquireCounter = Synchronized<Int>(0)
            var acquireCount: Int { acquireCounter.wrappedValue }

            /// Triggers this harness has built, held for its lifetime as module state holds one in
            /// production. `refreshIfPossible` captures `[weak self]`, so a trigger owned only by a
            /// local `let` can be released before its task runs, and the decision silently returns.
            private var triggers: [GeofenceRefreshTrigger] = []

            init() {
                // An unstubbed generated mock force-unwraps and takes the whole process down.
                coordinator.refreshReturnValue = .success(())
                coordinator.resetReturnValue = .success(())
                self.root = FileManager.default.temporaryDirectory.appendingPathComponent("trigger-\(UUID().uuidString)")
                self.storage = GeofenceStorage(directoryURL: root.appendingPathComponent("storage"))
                self.contextStore = BackgroundDeliveryContextStore(
                    fileManager: .default,
                    directoryURL: root.appendingPathComponent("context")
                )
            }

            deinit { try? FileManager.default.removeItem(at: root) }

            func makeTrigger(locationMode: GeofenceLocationMode = .automatic) -> GeofenceRefreshTrigger {
                let trigger = GeofenceRefreshTrigger(
                    storage: storage,
                    contextStore: contextStore,
                    coordinator: { [coordinator] in coordinator },
                    logger: LoggerMock(),
                    locationMode: locationMode,
                    explicitRefreshRequested: explicitRefreshRequested,
                    lastKnownLocation: { [weak self] in
                        self?.onLastKnownRead?()
                        return self?.lastKnown
                    },
                    acquireFix: { [weak self] in self?.acquireCounter.mutating { $0 += 1 } }
                )
                triggers.append(trigger)
                return trigger
            }
        }

        @Test
        func onModuleInit_givenNoIdentifiedUser_expectNoRefreshAndNoFixRequest() async {
            let harness = Harness()
            harness.lastKnown = LocationData(latitude: 1, longitude: 2)

            let trigger = harness.makeTrigger()
            trigger.onModuleInit()
            await settleQuietly(windowForAbsence)

            #expect(harness.coordinator.refreshCallsCount == 0)
            #expect(harness.acquireCount == 0, "a signed-out launch must not spend a GPS fix")
        }

        @Test
        func onIdentified_givenBothAnchors_expectRegistrationCentrePreferred() async {
            let harness = Harness()
            harness.contextStore.setUserId("u")
            harness.lastKnown = LocationData(latitude: 10, longitude: 10)
            await harness.storage.recordRegistration(center: LocationData(latitude: 55, longitude: 66), businessIds: [])

            let trigger = harness.makeTrigger()
            trigger.onIdentified()
            #expect(await settle(timeout: waitForDetachedWork) { harness.coordinator.refreshCallsCount == 1 })

            #expect(harness.coordinator.refreshReceivedArguments?.latitude == 55)
            #expect(harness.coordinator.refreshReceivedArguments?.longitude == 66)
        }

        @Test
        func onIdentified_givenOnlyLastKnown_expectRefreshFromIt() async {
            let harness = Harness()
            harness.contextStore.setUserId("u")
            harness.lastKnown = LocationData(latitude: 10, longitude: 20)

            let trigger = harness.makeTrigger()
            trigger.onIdentified()
            #expect(await settle(timeout: waitForDetachedWork) { harness.coordinator.refreshCallsCount == 1 })

            #expect(harness.coordinator.refreshReceivedArguments?.latitude == 10)
            #expect(harness.acquireCount == 0, "an anchor existed, so no fix should have been requested")
        }

        @Test
        func onIdentified_givenNoAnchorInAutomatic_expectArmedAndFixRequested() async {
            let harness = Harness()
            harness.contextStore.setUserId("u")
            let trigger = harness.makeTrigger(locationMode: .automatic)

            trigger.onIdentified()
            #expect(await settle(timeout: waitForDetachedWork) { harness.acquireCount == 1 })
            #expect(harness.coordinator.refreshCallsCount == 0)

            trigger.onLocationAcquired(LocationData(latitude: 31, longitude: 74))
            #expect(await settle(timeout: waitForDetachedWork) { harness.coordinator.refreshCallsCount == 1 })
            #expect(harness.coordinator.refreshReceivedArguments?.latitude == 31)
        }

        @Test
        func onIdentified_givenNoAnchorInManual_expectArmedButNoFixRequested() async {
            let harness = Harness()
            harness.contextStore.setUserId("u")

            let trigger = harness.makeTrigger(locationMode: .manual)
            trigger.onIdentified()
            await settleQuietly(windowForAbsence)

            #expect(harness.acquireCount == 0, "manual mode waits for the host to supply a fix")
        }

        @Test
        func onLocationAcquired_givenSecondFix_expectArmingConsumedOnce() async {
            let harness = Harness()
            harness.contextStore.setUserId("u")
            let trigger = harness.makeTrigger()

            trigger.onIdentified()
            #expect(await settle(timeout: waitForDetachedWork) { harness.acquireCount == 1 })

            trigger.onLocationAcquired(LocationData(latitude: 31, longitude: 74))
            #expect(await settle(timeout: waitForDetachedWork) { harness.coordinator.refreshCallsCount == 1 })
            trigger.onLocationAcquired(LocationData(latitude: 32, longitude: 75))
            await settleQuietly(windowForAbsence)

            #expect(harness.coordinator.refreshCallsCount == 1)
        }

        @Test
        func onLocationAcquired_givenNothingArmed_expectNoRefresh() async {
            let harness = Harness()
            harness.contextStore.setUserId("u")
            harness.lastKnown = LocationData(latitude: 1, longitude: 2)
            let trigger = harness.makeTrigger()

            trigger.onModuleInit()
            #expect(await settle(timeout: waitForDetachedWork) { harness.coordinator.refreshCallsCount == 1 })
            harness.coordinator.resetMock()

            trigger.onLocationAcquired(LocationData(latitude: 9, longitude: 9))
            await settleQuietly(windowForAbsence)

            #expect(harness.coordinator.refreshCallsCount == 0)
        }

        @Test
        func onLocationAcquired_givenRequestMadeBeforeSetup_expectHonoured() async {
            let harness = Harness()
            harness.contextStore.setUserId("u")
            harness.explicitRefreshRequested.wrappedValue = true

            let trigger = harness.makeTrigger()
            trigger.onLocationAcquired(LocationData(latitude: 44, longitude: 45))
            #expect(await settle(timeout: waitForDetachedWork) { harness.coordinator.refreshCallsCount == 1 })

            #expect(harness.coordinator.refreshReceivedArguments?.latitude == 44)
        }

        /// `onReset` clears two arm flags. This covers the one a no-anchor decision sets;
        /// `explicitRefreshRequested` is covered below.
        @Test
        func onReset_givenArmedByAMissingAnchor_expectTheArmingDropped() async {
            let harness = Harness()
            harness.contextStore.setUserId("u")
            let trigger = harness.makeTrigger(locationMode: .automatic)

            // No anchor of either kind, so the decision arms and asks for a fix instead of refreshing.
            trigger.onIdentified()
            #expect(await settle(timeout: waitForDetachedWork) { harness.acquireCount == 1 })
            #expect(harness.coordinator.refreshCallsCount == 0)

            trigger.onReset()
            #expect(await settle(timeout: waitForDetachedWork) { harness.coordinator.resetCallsCount == 1 })

            // The fix that arming asked for arrives, but the user who asked for it has signed out.
            trigger.onLocationAcquired(LocationData(latitude: 9, longitude: 9))
            await settleQuietly(windowForAbsence)

            #expect(
                harness.coordinator.refreshCallsCount == 0,
                "a signed-out user's arming must not spend the next user's first fix"
            )
        }

        @Test
        func onReset_expectPendingRequestDroppedSoNextUserDoesNotInheritIt() async {
            let harness = Harness()
            harness.contextStore.setUserId("u")
            harness.explicitRefreshRequested.wrappedValue = true
            let trigger = harness.makeTrigger()

            trigger.onReset()
            #expect(await settle(timeout: waitForDetachedWork) { harness.coordinator.resetCallsCount == 1 })
            #expect(harness.coordinator.resetCallsCount == 1)

            trigger.onLocationAcquired(LocationData(latitude: 44, longitude: 45))
            await settleQuietly(windowForAbsence)
            #expect(harness.coordinator.refreshCallsCount == 0)
        }

        /// A late `ResetEvent` for a *prior* user must not abort the current user's decision.
        ///
        /// After `clearIdentify()` → `identify("B")`, the reset can arrive (unordered bus) while B's
        /// decision is running. Aborting would leave B with no geofences, since the coordinator's
        /// own reset is superseded and would not register them either.
        @Test
        func onIdentified_givenLateResetForPriorUserMidDecision_expectRefreshStillRuns() async {
            let harness = Harness()
            harness.contextStore.setUserId("B")
            harness.lastKnown = LocationData(latitude: 10, longitude: 20)
            let trigger = harness.makeTrigger()
            // The reset lands mid-reads: it clears the arm flags but leaves B the current user.
            harness.onLastKnownRead = { [weak trigger] in trigger?.onReset() }

            trigger.onIdentified()

            #expect(
                await settle(timeout: waitForDetachedWork) { harness.coordinator.refreshCallsCount == 1 },
                "a late reset for a prior user dropped the current user's refresh"
            )
        }
    }
}
