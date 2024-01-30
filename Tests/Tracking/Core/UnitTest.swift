@testable import CioDataPipelines
@testable import CioInternalCommon
@testable import CioTracking
import Foundation
@testable import Segment
import SharedTests

open class UnitTest: SharedTests.UnitTest {
    // Use this `CustomerIO` instance when invoking `CustomerIOInstance` functions in unit tests.
    // This ensures convenience and consistency across unit tests, and guarantees the correct instance is used for testing.
    open var customerIO: CustomerIO!

    override open func setUpDependencies() {
        super.setUpDependencies()

        diGraph.override(value: dateUtilStub, forType: DateUtil.self)
    }

    override open func initializeSDKComponents() -> CustomerIO? {
        // creates CustomerIO instance and set necessary values for testing
        let implementation = DataPipeline.createAndSetSharedTestInstance(
            diGraphShared: diGraphShared,
            config: DataPipelineConfigOptions.Factory.create(sdkConfig: sdkConfig)
        )

        // creates CustomerIO instance and set necessary values for testing
        customerIO = CustomerIO(implementation: implementation, diGraph: diGraph)

        return customerIO
    }

    // function meant to only be in tests as deleting all files from a search path (where app files can be stored!) is
    // not a good idea.
    override open func deleteAllFiles() {
        super.deleteAllFiles()

        let fileManager = FileManager.default

        let deleteFromSearchPath: (FileManager.SearchPathDirectory) -> Void = { path in
            // OK to use try! here as we want tests to crash if for some reason we are not able to delete files from the
            // device.
            // if files do not get deleted between tests, we could have false positive tests.
            // swiftlint:disable:next force_try
            let pathUrl = try! fileManager.url(for: path, in: .userDomainMask, appropriateFor: nil, create: false)
            // swiftlint:disable:next force_try
            let fileURLs = try! fileManager.contentsOfDirectory(
                at: pathUrl,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            for fileURL in fileURLs {
                try? fileManager.removeItem(at: fileURL)
            }
        }

        deleteFromSearchPath(.applicationSupportDirectory)
    }
}
