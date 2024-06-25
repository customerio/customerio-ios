import CioInternalCommon
import Foundation

// Allows us to mock EngineWeb instances for testing.
protocol EngineWebProvider {
    func getEngineWebInstance(configuration: EngineWebConfiguration) -> EngineWebInstance
}

// sourcery: InjectRegisterShared = "EngineWebProvider"
class EngineWebProviderImpl: EngineWebProvider {
    func getEngineWebInstance(configuration: EngineWebConfiguration) -> EngineWebInstance {
        EngineWeb(configuration: configuration)
    }
}
