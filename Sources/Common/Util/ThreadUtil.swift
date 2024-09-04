import Foundation

// allows us to more easily have automated tests with threading
public protocol ThreadUtil {
    func runBackground(_ block: @escaping () -> Void)
    func runMain(_ block: @escaping () -> Void)
    func runMainAfterDelay(deadline: DispatchTime, _ block: @escaping () -> Void)
}

// sourcery: InjectRegisterShared = "ThreadUtil"
public class CioThreadUtil: ThreadUtil {
    public func runMain(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }

    public func runMainAfterDelay(deadline: DispatchTime, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: deadline, execute: block)
    }

    public func runBackground(_ block: @escaping () -> Void) {
        DispatchQueue.global(qos: .background).async(execute: block)
    }
}
