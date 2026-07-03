@testable import CioLocationGeofence
import Foundation
import Testing

@Suite("GeofenceModule")
struct GeofenceModuleTests {
    @Test
    func moduleName_expectGeofence() {
        #expect(GeofenceModule().moduleName == "Geofence")
    }

    @Test
    func initialize_givenDefaultConfig_expectNoCrash() {
        // Scaffold module performs no setup yet; this guards the no-op contract.
        GeofenceModule().initialize()
    }

    @Test
    func config_defaultLocationMode_isAutomatic() {
        #expect(GeofenceModuleConfig().locationMode == .automatic)
    }

    @Test
    func config_givenExplicitLocationMode_isStored() {
        #expect(GeofenceModuleConfig(locationMode: .manual).locationMode == .manual)
    }
}
