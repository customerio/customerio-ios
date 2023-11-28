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
        let instance = alreadyCreatedImplementation ?? createAndSetImplementationInstance()
        if instance == nil {
            logger.info("Module \(moduleName) is not yet initialized")
        }
        return instance
    }
    
    // To identify the module in top-level objects and within log messages
    let moduleName: String
    open var logger: Logger {
        DIGraphShared.shared.logger
    }

    // singleton constructor
    // optionally accepts implementation instance for facilitating testing, allowing injection
    // of a mock or stub implementation.
    public init(moduleName: String, implementation: ImplementationClass? = nil) {
        self.moduleName = moduleName
        self.alreadyCreatedImplementation = implementation
    }

    private func createAndSetImplementationInstance() -> ImplementationClass? {
        let newInstance = getImplementationInstance()
        alreadyCreatedImplementation = newInstance
        return newInstance
    }

    open func setImplementationInstance(implementation: ImplementationClass?) {
        alreadyCreatedImplementation = implementation
    }

    // Feature modules (e.g. push) which support auto-initialization without client configuration can
    // provide its instance here to ensure early initialization upon the first call
    // Feature modules (e.g. in-app) that require user input for initialization may not override this
    // method or can return `nil`.
    open func getImplementationInstance() -> ImplementationClass? {
        return nil
    }
}
