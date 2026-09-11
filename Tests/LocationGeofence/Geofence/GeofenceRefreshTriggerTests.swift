@testable import CioInternalCommon
@testable import CioInternalCommonMocks
@testable import CioLocationGeofence
@testable import CioLocationGeofenceMocks
import Foundation
import SharedTests
import Testing

@Suite("GeofenceRefreshTrigger")
struct GeofenceRefreshTriggerTests {
    private final class Harness {
        let coordinator = GeofenceSyncCoordinatorMock()
        let contextStore: BackgroundDeliveryContextStore
        let storage: GeofenceStorage
        let explicitRefreshRequested = Synchronized<Bool>(false)
        var acquireCount = 0
        var lastKnown: LocationData?
        private let root: URL

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
            GeofenceRefreshTrigger(
                storage: storage,
                contextStore: contextStore,
                coordinator: { [coordinator] in coordinator },
                logger: LoggerMock(),
                locationMode: locationMode,
                explicitRefreshRequested: explicitRefreshRequested,
                lastKnownLocation: { [weak self] in self?.lastKnown },
                acquireFix: { [weak self] in self?.acquireCount += 1 }
            )
        }
    }

    @Test
    func onModuleInit_givenNoIdentifiedUser_expectNoRefreshAndNoFixRequest() async {
        let harness = Harness()
        harness.lastKnown = LocationData(latitude: 1, longitude: 2)

        let trigger = harness.makeTrigger()
        trigger.onModuleInit()
        await settleQuietly()

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
        #expect(await settle { harness.coordinator.refreshCallsCount == 1 })

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
        #expect(await settle { harness.coordinator.refreshCallsCount == 1 })

        #expect(harness.coordinator.refreshReceivedArguments?.latitude == 10)
        #expect(harness.acquireCount == 0, "an anchor existed, so no fix should have been requested")
    }

    @Test
    func onIdentified_givenNoAnchorInAutomatic_expectArmedAndFixRequested() async {
        let harness = Harness()
        harness.contextStore.setUserId("u")
        let trigger = harness.makeTrigger(locationMode: .automatic)

        trigger.onIdentified()
        #expect(await settle { harness.acquireCount == 1 })
        #expect(harness.coordinator.refreshCallsCount == 0)

        trigger.onLocationAcquired(LocationData(latitude: 31, longitude: 74))
        #expect(await settle { harness.coordinator.refreshCallsCount == 1 })
        #expect(harness.coordinator.refreshReceivedArguments?.latitude == 31)
    }

    @Test
    func onIdentified_givenNoAnchorInManual_expectArmedButNoFixRequested() async {
        let harness = Harness()
        harness.contextStore.setUserId("u")

        let trigger = harness.makeTrigger(locationMode: .manual)
        trigger.onIdentified()
        await settleQuietly()

        #expect(harness.acquireCount == 0, "manual mode waits for the host to supply a fix")
        // Held to here: the decision captures the trigger weakly, so a temporary would deallocate.
        _ = trigger
    }

    @Test
    func onLocationAcquired_givenSecondFix_expectArmingConsumedOnce() async {
        let harness = Harness()
        harness.contextStore.setUserId("u")
        let trigger = harness.makeTrigger()

        trigger.onIdentified()
        #expect(await settle { harness.acquireCount == 1 })

        trigger.onLocationAcquired(LocationData(latitude: 31, longitude: 74))
        #expect(await settle { harness.coordinator.refreshCallsCount == 1 })
        trigger.onLocationAcquired(LocationData(latitude: 32, longitude: 75))
        await settleQuietly()

        #expect(harness.coordinator.refreshCallsCount == 1)
    }

    @Test
    func onLocationAcquired_givenNothingArmed_expectNoRefresh() async {
        let harness = Harness()
        harness.contextStore.setUserId("u")
        harness.lastKnown = LocationData(latitude: 1, longitude: 2)
        let trigger = harness.makeTrigger()

        trigger.onModuleInit()
        #expect(await settle { harness.coordinator.refreshCallsCount == 1 })
        harness.coordinator.resetMock()

        trigger.onLocationAcquired(LocationData(latitude: 9, longitude: 9))
        await settleQuietly()

        #expect(harness.coordinator.refreshCallsCount == 0)
    }

    @Test
    func onLocationAcquired_givenRequestMadeBeforeSetup_expectHonoured() async {
        let harness = Harness()
        harness.contextStore.setUserId("u")
        harness.explicitRefreshRequested.wrappedValue = true

        let trigger = harness.makeTrigger()
        trigger.onLocationAcquired(LocationData(latitude: 44, longitude: 45))
        #expect(await settle { harness.coordinator.refreshCallsCount == 1 })

        #expect(harness.coordinator.refreshReceivedArguments?.latitude == 44)
    }

    @Test
    func onReset_expectPendingRequestDroppedSoNextUserDoesNotInheritIt() async {
        let harness = Harness()
        harness.contextStore.setUserId("u")
        harness.explicitRefreshRequested.wrappedValue = true
        let trigger = harness.makeTrigger()

        trigger.onReset()
        #expect(await settle { harness.coordinator.resetCallsCount == 1 })
        #expect(harness.coordinator.resetCallsCount == 1)

        trigger.onLocationAcquired(LocationData(latitude: 44, longitude: 45))
        await settleQuietly()
        #expect(harness.coordinator.refreshCallsCount == 0)
    }
}
