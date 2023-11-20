import Foundation

public protocol DIManager: AnyObject {
    var overrides: [String: Any] { get set }
    var singletons: [String: Any] { get set }

    func override<T: Any>(value: T, forType type: T.Type)
    func getOverriddenInstance<T: Any>() -> T?
    func reset()
}

public extension DIManager {
    /**
     Designed to be used only in test classes to override dependencies.

     ```
     let mockOffRoadWheels = // make a mock of OffRoadWheels class
     DIGraph.shared.override(mockOffRoadWheels, OffRoadWheels.self)
     ```
     */
    func override<T>(value: T, forType type: T.Type) {
        overrides[String(describing: type)] = value
    }

    // Retrieves an overridden instance of a specified type from the `overrides` dictionary.
    // If an overridden instance exists and can be cast to the specified type, it is returned; otherwise, nil is returned.
    func getOverriddenInstance<T: Any>() -> T? {
        // Get the type name as the key for the dictionary.
        let typeName = String(describing: T.self)

        guard overrides[typeName] != nil else {
            return nil // no override set. Quit early.
        }

        // Get and cast the overridden instance from the dictionary.
        guard let overriddenInstance = overrides[typeName] as? T else {
            fatalError("Failed to cast overridden instance to type '\(typeName)'.")
        }

        return overriddenInstance
    }

    // Reset the DI graph (useful for testing)
    func reset() {
        singletons = [:]
        overrides = [:]
    }
}
