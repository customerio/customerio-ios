import Foundation

// allows us to more easily have automated tests with threading
public protocol ThreadUtil {
    func runBackground(_ block: @escaping @Sendable () -> Void)
    func runMain(_ block: @escaping @Sendable () -> Void)
}

// sourcery: InjectRegisterShared = "ThreadUtil"
public class CioThreadUtil: ThreadUtil {
    public func runMain(_ block: @escaping @Sendable () -> Void) {
        DispatchQueue.main.async(execute: block)
    }

    public func runBackground(_ block: @escaping @Sendable () -> Void) {
        DispatchQueue.global(qos: .background).async(execute: block)
    }
}
