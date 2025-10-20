import Foundation

public protocol DIManager: AnyObject {
    func override<T: Any>(value: T, forType type: T.Type)
    func getOverriddenInstance<T: Any>() -> T?
    func reset()

    // Used internally by generated code
    func getOrCreateSingleton<T>(forType type: T.Type, factory: () -> T) -> T
}
