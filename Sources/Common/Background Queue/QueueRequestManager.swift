import Foundation

/**
 Simple singleton that helps assert that the background queue is only running
 one run request at one time (1 run request per site id since each site id can have it's own background queue).

 When the background queue wants to run it's tasks, it's important that the queue only have 1 concurrent runner
 running at one time to prevent race conditions and tasks running multiple times.

 This class is small and separate from the rest of the queue logic for some readability/scalability value but
 mostly memory safety by keeping dependencies low in class (prefer none).
 */
public protocol QueueRequestManager: AutoMockable {
    /// call when a runner run request is complete
    func requestComplete()
    /// call when a new run request is requested.
    /// returns `true` if the queue is already running.
    func startIfNotAlready() -> Bool
}

// sourcery: InjectRegister = "QueueRequestManager"
// sourcery: InjectSingleton
public class CioQueueRequestManager: QueueRequestManager {
    @Atomic var isRunningRequest = false

    public func requestComplete() {
        isRunningRequest = false
    }

    public func startIfNotAlready() -> Bool {
        let isQueueRunningARequest = isRunningRequest

        if !isQueueRunningARequest {
            isRunningRequest = true
        }

        // return the isRunningRequest value before modification or we will
        // *always* return true (since we modify to true or ignore)
        return isQueueRunningARequest
    }
}
