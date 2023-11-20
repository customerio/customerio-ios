import Foundation

public class DIServiceGraph {
    public static let shared: DIServiceGraph = .init()

    var singletons: [String: Any] = [:]
    var overrides: [String: Any] = [:]

    init() {}

    // Add a singleton service
    public func addSingleton<T>(_ instance: T, forType type: T.Type) {
        singletons[String(describing: type)] = instance
    }

    // Retrieve a singleton service
    public func getSingleton<T>(ofType type: T.Type) -> T? {
        let typeName = String(describing: type)
        if let override = overrides[typeName] as? T {
            return override
        }
        return singletons[typeName] as? T
    }

    // Override a service for testing
    public func override<T>(value: T, forType type: T.Type) {
        overrides[String(describing: type)] = value
    }

    // Reset the DI graph (useful for testing)
    public func reset() {
        singletons = [:]
        overrides = [:]
    }
}
