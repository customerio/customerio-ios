@testable import CioInternalCommon
@testable import CioLocation
import CoreLocation
import SharedTests
import Testing

@Suite("Location")
struct UninitializedLocationServicesTests {
    @Test
    func setLastKnownLocation_expectLoggerModuleNotInitializedCalled() {
        let loggerMock = LoggerMock()
        let service = UninitializedLocationServices(logger: loggerMock)
        let validLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)

        service.setLastKnownLocation(validLocation)

        #expect(loggerMock.errorCallsCount == 1)
        #expect(
            loggerMock.errorReceivedInvocations.first?.message
                == "Location module is not initialized. Add LocationModule via SDKConfigBuilder.addModule(LocationModule(config: ...)) before CustomerIO.initialize(withConfig:)."
        )
    }
}
