import Foundation

// allows us to more easily have automated tests with threading
public protocol ThreadUtil {
    // These functions use a global queue that the SDK shares.
    func queueOnBackground(_ block: @escaping () -> Void)
    func queueOnMain(_ block: @escaping () -> Void)

    // These allow you to use a new queue and not the global queue.
    func queueOnBackground(id: String, block: @escaping () -> Void)
}

// sourcery: InjectRegister = "ThreadUtil"
public class CioThreadUtil: ThreadUtil {
    public func queueOnMain(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }

    public func queueOnBackground(_ block: @escaping () -> Void) {
        DispatchQueue.global(qos: .background).async(execute: block)
    }

    public func queueOnBackground(id: String, block: @escaping () -> Void) {
        DispatchQueue(label: id).async(execute: block)
    }
}
