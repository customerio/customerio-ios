@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import Foundation
import SharedTests
import Testing

/// Bound for every wait for something to happen.
///
/// The default two seconds is enough on a quiet machine and not enough on CI, where the whole
/// package's suites run in parallel and this one's decisions have to reach the main actor through
/// that contention. It is not a stuck-versus-working question: on one CI run the refresh landed
/// *after* its wait had given up and the mock had been reset, which is how
/// `onLocationAcquired_givenNothingArmed_expectNoRefresh` came to see the call it asserts is absent.
/// These are eventually-assertions, so the bound only decides how long a genuine failure takes to
/// report — a passing wait returns as soon as the condition holds.
private let waitForDetachedWork: TimeInterval = 10

/// Window for every assertion that something does *not* happen.
///
/// A negative cannot be waited for by outcome — it can only be given long enough that the thing it
/// forbids would have happened. `settleQuietly`'s 0.3 s default is far shorter than the contention
/// the bound above exists to absorb, so these were passing because nothing had arrived yet rather
/// than because nothing would. Unlike the bound above, this one is paid on every green run.
private let windowForAbsence: TimeInterval = 2

/// Nested under `SharedDIGraphSuites` because `GeofenceStorage.init` defaults its `dateUtil` to
/// `DIGraphShared.shared.dateUtil`, so every `Harness` reads the shared graph. Running in parallel
/// with the other suites that write it is what produced the contention these waits were widened
/// for; taking turns is the fix, and the widened bound below is only the backstop.
extension SharedDIGraphSuites {
    @Suite("GeofenceRefreshTrigger")
    struct GeofenceRefreshTriggerTests {
        private final class Harness {
            let coordinator = GeofenceSyncCoordinatorMock()
            let contextStore: BackgroundDeliveryContextStore
            let storage: GeofenceStorage
            let explicitRefreshRequested = Synchronized<Bool>(false)

            /// Read from the trigger's decision task and written from the test thread, so it is
            /// guarded for the same reason `acquireCounter` below is.
            private let lastKnownBox = Synchronized<LocationData?>(nil)
            var lastKnown: LocationData? {
                get { lastKnownBox.wrappedValue }
                set { lastKnownBox.wrappedValue = newValue }
            }

            private let root: URL

            /// `acquireFix` is called from the trigger's decision task, not from the test's thread, and
            /// every wait below polls this from a third. A plain `var` read and written across those is
            /// a race whose usual symptom is a neighbouring read going wrong, not this counter.
            private let acquireCounter = Synchronized<Int>(0)
            var acquireCount: Int { acquireCounter.wrappedValue }

            /// Triggers this harness has built, held for its lifetime.
            ///
            /// `refreshIfPossible` does its work in `Task { @MainActor [weak self] }`, so a trigger owned
            /// only by a local `let` can be released once a test makes its last direct use of it, before
            /// that task's first hop resumes — the decision then finds `self` nil and silently returns.
            /// Not what the CI failures in this file were: there the work arrived late, not never. The
            /// hazard is real all the same, and one test used to guard against it by hand.
            ///
            /// Production ownership is exactly this — module state holds the trigger for the process —
            /// so holding it here is the realistic arrangement, not a prop for the test.
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
                    lastKnownLocation: { [weak self] in self?.lastKnown },
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

        /// The other half of `onReset`'s clear. `explicitRefreshRequested` is covered below; this
        /// flag is armed by a different route — a decision that ran and found no anchor — and had
        /// no coverage at all, so deleting the line that clears it left the suite green.
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
    }
}
