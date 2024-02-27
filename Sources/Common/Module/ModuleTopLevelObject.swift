import Foundation

// Base class meant to be subclassed by top-level classes such as `MessagingPush` and `MessagingInApp`. Provides some
// boilerplate logic to creating an implementation object
// once the SDK has finally been initialized.
//
// Top-level class meaning it contains public facing SDK functions called by customers.
// There isn't a constructor populated via dependency injection. It's at the top node
// of dependencies.
open class ModuleTopLevelObject<ImplementationClass> {
    /*
     It's preferred to get a lock from lockmanager. Because subclasses will be a singleton, we can create a lock instance that will be shared in all calls to this class.
     */
    private let lock = Lock.unsafeInit()
    public var hasBeenInitialized: Bool {
        _implementation != nil
    }

    @Atomic public var _implementation: ImplementationClass?

    public var implementation: ImplementationClass? {
        guard let _implementation else {
            logger.info("Module \(moduleName) is not yet initialized. All requests made to module \(moduleName) will be ignored until it is initialized. See docs for help.")
            return nil
        }

        return _implementation
    }

    // To identify the module in top-level objects and within log messages
    public let moduleName: String

    open var logger: Logger {
        DIGraphShared.shared.logger
    }

    // singleton constructor
    // optionally accepts implementation instance for facilitating testing, allowing injection
    // of a mock or stub implementation.
    public init(moduleName: String, implementation: ImplementationClass? = nil) {
        self.moduleName = moduleName
        self._implementation = implementation
    }

    // Subclasses call this function when they want to initialize the module. Must return an implementation object because the instance
    // is what determines that a module has been initialized.
    public func initializeModuleIfNotAlready(_ blockToInitializeModule: () -> ImplementationClass) {
        // Make this function thread-safe by immediately locking it.
        lock.lock()
        defer {
            lock.unlock()
        }

        // Make sure module is only initialized one time.
        if hasBeenInitialized {
            logger.info("\(moduleName) module is already initialized. Ignoring redundant initialization request.")
            return
        }

        logger.debug("Setting up \(moduleName) module...")
        _implementation = blockToInitializeModule()
        logger.info("\(moduleName) module successfully set up with SDK")
    }
}
