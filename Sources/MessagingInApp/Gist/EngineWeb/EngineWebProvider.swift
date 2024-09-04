import CioInternalCommon
import Foundation

// Allows us to mock EngineWeb instances for testing.
protocol EngineWebProvider {
    func getEngineWebInstance(configuration: EngineWebConfiguration, state: InAppMessageState) -> EngineWebInstance
}

// sourcery: InjectRegisterShared = "EngineWebProvider"
class EngineWebProviderImpl: EngineWebProvider {
    func getEngineWebInstance(configuration: EngineWebConfiguration, state: InAppMessageState) -> EngineWebInstance {
        EngineWeb(configuration: configuration, state: state)
    }
}
