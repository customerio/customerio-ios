import Common
import Foundation

// Base class meant to be subclassed by top-level classes such as `MessagingPush` and `MessagingInApp`. Provides some
// boilerplate logic to creating an implementation object
// once the SDK has finally been initialized.
//
// Top-level class meaning it contains public facing SDK functions called by customers.
// There isn't a constructor populated via dependency injection. It's at the top node
// of dependencies.
open class ModuleTopLevelObject<ImplementationClass> {
    private(set) var alreadyCreatedImplementation: ImplementationClass?
    public var implementation: ImplementationClass? {
        alreadyCreatedImplementation ?? createAndSetImplementationInstance()
    }

    private let sdkInitializedUtil: SdkInitializedUtil

    // for writing tests
    public init(implementation: ImplementationClass, sdkInitializedUtil: SdkInitializedUtil) {
        self.alreadyCreatedImplementation = implementation
        self.sdkInitializedUtil = sdkInitializedUtil
    }

    // singleton constructor
    public init() {
        self.sdkInitializedUtil = SdkInitializedUtilImpl()
    }

    private func createAndSetImplementationInstance() -> ImplementationClass? {
        guard let postSdkInitializedData = sdkInitializedUtil.postInitializedData else {
            // SDK not yet initialized. Don't run the code.
            return nil
        }

        let newInstance = getImplementationInstance(diGraph: postSdkInitializedData.diGraph)
        alreadyCreatedImplementation = newInstance
        return newInstance
    }

    // We want each top level module to have an initialize function so that features like hooks get setup as soon as the
    // SDK is initialized.
    public func initialize() {
        guard let postSdkInitializedData = sdkInitializedUtil.postInitializedData else {
            // SDK not yet initialized. Don't run the code.
            return
        }

        inititlize(diGraph: postSdkInitializedData.diGraph)
    }

    open func inititlize(diGraph: DIGraph) {
        fatalError("forgot to override in subclass")
    }

    open func getImplementationInstance(diGraph: DIGraph) -> ImplementationClass {
        fatalError("forgot to override in subclass")
    }
}
