@testable import CioMessagingInApp
import Foundation

class EngineWebProviderStub: EngineWebProvider {
    private(set) var lastConfiguration: EngineWebConfiguration?

    func getEngineWebInstance(configuration: EngineWebConfiguration, state: InAppMessageState, message: Message) -> any EngineWebInstance {
        lastConfiguration = configuration
        return engineWebMock
    }

    let engineWebMock: EngineWebInstance

    init(engineWebMock: EngineWebInstance) {
        self.engineWebMock = engineWebMock
    }
}
