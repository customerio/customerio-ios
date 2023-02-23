import Foundation

// allows us to more easily have automated tests with threading
public protocol ThreadUtil {
    // It's important that these functions work as a FIFO serial queue. Our code depends on the blocks of code being executed in order, not concurrently.
    // Create new functions if there is a use case for that.
    func queueOnBackground(_ block: @escaping () -> Void)
    func queueOnMain(_ block: @escaping () -> Void)
}

// sourcery: InjectRegister = "ThreadUtil"
public class CioThreadUtil: ThreadUtil {
    public func queueOnMain(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }

    public func queueOnBackground(_ block: @escaping () -> Void) {
        // The global background queue runs in a serial behavior. This is a snippet of the docs:
        // "For serial tasks, set the target of your serial queue to one of the global concurrent queues." You must add an option to make a queue concurrent.
        // Docs: https://developer.apple.com/documentation/dispatch/dispatchqueue
        DispatchQueue.global(qos: .background).async(execute: block)
    }
}
