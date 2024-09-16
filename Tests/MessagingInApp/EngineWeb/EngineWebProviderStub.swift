@testable import CioMessagingInApp
import Foundation

class EngineWebProviderStub: EngineWebProvider {
    func getEngineWebInstance(configuration: EngineWebConfiguration, state: InAppMessageState, message: Message) -> any EngineWebInstance {
        engineWebMock
    }

    let engineWebMock: EngineWebInstance

    init(engineWebMock: EngineWebInstance) {
        self.engineWebMock = engineWebMock
    }
}
