@testable import CioLocationGeofence
import Foundation
import Testing

extension SharedDIGraphSuites {
    @Suite("GeofenceModule")
    struct GeofenceModuleTests {
        @Test
        func moduleName_expectGeofence() {
            #expect(GeofenceModule().moduleName == "Geofence")
        }

        @Test
        func initialize_givenDefaultConfig_expectNoCrash() {
            // Runs the real bootstrap against `DIGraphShared.shared` on a detached task, which is why
            // this suite is nested under `SharedDIGraphSuites`.
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
}
