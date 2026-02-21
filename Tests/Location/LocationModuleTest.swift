import CioInternalCommon
import CioLocation
import Foundation
import Testing

@Suite("LocationModule")
struct LocationModuleTests {
    @Test
    func conformsToCustomerIOModule_expectModuleName() {
        let module = LocationModule(config: LocationConfig(enableLocationTracking: true))

        #expect(module.moduleName == "Location")
        // Conformance to CustomerIOModule (from Common) is verified at compile time; Location has no DataPipelines dependency.
        let asModule: any CustomerIOModule = module
        #expect(asModule.moduleName == "Location")
    }

    @Test
    func initialize_fromBackgroundThread_doesNotCrash() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                LocationModule(config: LocationConfig(enableLocationTracking: true)).initialize()
                continuation.resume()
            }
        }
    }
}
