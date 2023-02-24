import Foundation

public protocol ThreadUtil {
    // It's important that these functions work as a FIFO serial queue. Our code depends on the blocks of code being executed in order, not concurrently.
    // Create new functions if there is a use case for that.
    func queueOnBackground(_ block: @escaping () -> Void)
    func queueOnMain(_ block: @escaping () -> Void)
}

// Benefits of this object:
// 1. Allows us to mock threading behavior in unit tests if appropriate.
// 2. Our SDK can have a singleton queue that runs blocks of code on a background thread in FIFO order.
//
// Important: This class must be a singleton to only 1 queue object is used by the SDK code.
//
// sourcery: InjectRegister = "ThreadUtil"
// sourcery: InjectSingleton
public class CioThreadUtil: ThreadUtil {
    private let sharedBackgroundQueue = DispatchQueue(label: "io.customer.sdk.shared_background", qos: .background)

    public func queueOnMain(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }

    public func queueOnBackground(_ block: @escaping () -> Void) {
        sharedBackgroundQueue.async(execute: block)
    }
}
