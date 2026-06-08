@testable import CioInternalCommon
@testable import CioLocation
import SharedTests
import Testing

/// Regression guard for the no-op invariant: when the host app never adds the
/// Location module to `SDKConfigBuilder`, the Location target must contribute
/// no runtime side effects. All Location work is gated behind
/// `LocationModule.initialize()` → `LocationModuleState.shared.performInitialization`,
/// which `CustomerIO.initialize(withConfig:)` only invokes for modules present
/// in `config.modules`.
///
/// Builder-layer coverage that `SDKConfigBuilder` does not pre-load Location
/// lives in `SDKConfigBuilderTest.test_buildWithoutAddModule_expectEmptyModules`.
/// The tests below pin the Location-target half of that contract.
@Suite("LocationModuleAbsent")
struct LocationModuleAbsentTests {
    @Test
    func locationModuleStateCurrent_givenInitializeNotRun_expectUninitializedFacade() {
        // `LocationModuleState.shared.current` defaults to `UninitializedLocationServices`
        // and only flips once `performInitialization` runs on the main thread.
        // No test in this target invokes that path, so the default is observable.
        let current = LocationModuleState.shared.current

        #expect(current is UninitializedLocationServices)
    }

    @Test
    func uninitializedLocationServices_requestLocationUpdate_expectLogModuleNotInitialized() {
        let loggerMock = LoggerMock()
        let service = UninitializedLocationServices(logger: loggerMock)

        service.requestLocationUpdate()

        #expect(loggerMock.errorCallsCount == 1)
        #expect(
            loggerMock.errorReceivedInvocations.first?.message
                == "Location module is not initialized. Add LocationModule via SDKConfigBuilder.addModule(LocationModule(config: ...)) before CustomerIO.initialize(withConfig:)."
        )
    }
}
