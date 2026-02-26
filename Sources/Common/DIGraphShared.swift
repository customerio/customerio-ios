import Foundation

public final class DIGraphShared: @unchecked Sendable {
    public static let shared: DIGraphShared = .init()

    private let lock = NSRecursiveLock()
    private var singletons: [String: Any] = [:]
    private var overrides: [String: Any] = [:]

    /**
     Designed to be used only in test classes to override dependencies.

     ```
     let mockOffRoadWheels = // make a mock of OffRoadWheels class
     DIGraph.shared.override(mockOffRoadWheels, OffRoadWheels.self)
     ```
     */
    public func override<T>(value: T, forType type: T.Type) {
        lock.withLock {
            overrides[String(describing: type)] = value
        }
    }

    // Retrieves an overridden instance of a specified type from the `overrides` dictionary.
    // If an overridden instance exists and can be cast to the specified type, it is returned; otherwise, nil is returned.
    public func getOverriddenInstance<T: Any>() -> T? {
        // Get the type name as the key for the dictionary.
        let typeName = String(describing: T.self)

        return lock.withLock {
            overrides[typeName] as? T
        }
    }

    /// Returns a previously registered instance for the given type, or nil if none was registered.
    /// Use this for optional dependencies (e.g. modules that register themselves when initialized).
    /// Overrides (test mocks) take precedence over registered instances.
    public func getOptional<T: Any>(_ type: T.Type = T.self) -> T? {
        lock.withLock {
            let typeName = String(describing: type)
            if let overridden = overrides[typeName] as? T {
                return overridden
            }
            return singletons[typeName] as? T
        }
    }

    /// Registers an instance for the given type. Later resolution via `getOptional(_:)` will return this instance.
    /// Used when a module provides an implementation at initialization (e.g. DataPipelines registering as DataPipelineTracking).
    public func register<T: Any>(_ value: T, forType type: T.Type) {
        lock.withLock {
            singletons[String(describing: type)] = value
        }
    }

    /// Gets a singleton instance of the specified type T. If that instance doesn't exist,
    /// it is created using the provided factory closure, stored, and then returned.
    /// Parameters:
    /// - type: The type of the singleton instance to retrieve or create.
    /// - factory: A closure that creates a new instance of type T if one does not already exist.
    public func getSingletonOrCreate<T>(of type: T.Type = T.self, with factory: () -> T) -> T {
        let typeName = String(describing: type)
        return lock.withLock {
            let existingInstance = singletons[typeName] as? T
            if let instance = existingInstance {
                return instance
            } else {
                let newInstance = factory()
                singletons[typeName] = newInstance
                return newInstance
            }
        }
    }

    // Reset the DI graph (useful for testing)
    public func reset() {
        lock.withLock {
            singletons = [:]
            overrides = [:]
        }
    }
}
