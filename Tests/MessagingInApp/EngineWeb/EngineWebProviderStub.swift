@testable import CioMessagingInApp
import Foundation

class EngineWebProviderStub: EngineWebProvider {
    func getEngineWebInstance(configuration: CioMessagingInApp.EngineWebConfiguration, state: CioMessagingInApp.InAppMessageState, message: CioMessagingInApp.Message) -> any CioMessagingInApp.EngineWebInstance {
        engineWebMock
    }

    let engineWebMock: EngineWebInstance

    init(engineWebMock: EngineWebInstance) {
        self.engineWebMock = engineWebMock
    }
}
