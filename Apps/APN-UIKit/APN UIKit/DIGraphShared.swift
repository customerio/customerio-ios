import Foundation

public final class DIGraphShared: Sendable {
    private final class Locked<Value>: @unchecked Sendable {
        private var value: Value
        private let lock = NSLock()

        init(_ value: Value) {
            self.value = value
        }

        func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
            lock.lock()
            defer { lock.unlock() }
            return body(&value)
        }
    }

    private static let _shared: Locked<DIGraphShared> = .init(.init())
    public static var shared: DIGraphShared { _shared.withLock { $0 } }

    private let overrides: Locked<[String: Any]> = .init([:])
    private let singletons: Locked<[String: Any]> = .init([:])

    /**
     Designed to be used only in test classes to override dependencies.

     ```
     let mockOffRoadWheels = // make a mock of OffRoadWheels class
     DIGraph.shared.override(mockOffRoadWheels, OffRoadWheels.self)
     ```
     */
    public func override<T: Any>(value: T, forType type: T.Type) {
        overrides.withLock {
            $0[String(describing: type)] = value
        }
    }

    // Retrieves an overridden instance of a specified type from the `overrides` dictionary.
    // If an overridden instance exists and can be cast to the specified type, it is returned; otherwise, nil is returned.
    public func getOverriddenInstance<T: Any>() -> T? {
        // Get the type name as the key for the dictionary.
        let typeName = String(describing: T.self)
        return overrides.withLock { $0[typeName] } as? T
    }

    /**
     Reset graph. Meant to be used in `tearDown()` of tests.
     */
    public func reset() {
        overrides.withLock { $0 = [:] }
        singletons.withLock { $0 = [:] }
    }
}
