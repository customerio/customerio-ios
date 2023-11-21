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

    // for writing tests
    public init(implementation: ImplementationClass?) {
        self.alreadyCreatedImplementation = implementation
    }

    // singleton constructor
    public init() {
    }

    private func createAndSetImplementationInstance() -> ImplementationClass? {
        let newInstance = getImplementationInstance()
        alreadyCreatedImplementation = newInstance
        return newInstance
    }

    // We want each top level module to have an initialize function so that features get setup as early as possible
    open func inititlizeModule() {
        fatalError("forgot to override in subclass")
    }

    open func getImplementationInstance() -> ImplementationClass {
        fatalError("forgot to override in subclass")
    }
}
