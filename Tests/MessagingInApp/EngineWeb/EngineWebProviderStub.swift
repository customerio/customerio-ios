@testable import CioMessagingInApp
import Foundation

class EngineWebProviderStub: EngineWebProvider {
    let engineWebMock: EngineWebInstance

    init(engineWebMock: EngineWebInstance) {
        self.engineWebMock = engineWebMock
    }

    func getEngineWebInstance(configuration: EngineWebConfiguration) -> EngineWebInstance {
        engineWebMock
    }
}
