import Foundation

/**
 Simple singleton that helps assert that the background queue is only running
 one run request at one time (1 run request per site id since each site id can have it's own background queue).

 When the background queue wants to run it's tasks, it's important that the queue only have 1 concurrent runner
 running at one time to prevent race conditions and tasks running multiple times.
 */
public protocol QueueRequestManager: AutoMockable {
    /// call when a runner run request is complete
    func requestComplete()
    /// call when a new run request is requested. adds callback to list of callbacks
    /// to call when run request is done running.
    /// returns is an existing run request is currently running or not.
    func startRequest(onComplete: @escaping () -> Void) -> Bool
}

// sourcery: InjectRegister = "QueueRequestManager"
// sourcery: InjectSingleton
public class CioQueueRequestManager: QueueRequestManager {
    @Atomic private var isRunningRequest = false
    @Atomic private var callbacks: [() -> Void] = []

    public func requestComplete() {
        let existingCallbacks = callbacks

        callbacks = []
        isRunningRequest = false

        existingCallbacks.forEach { callback in
            callback()
        }
    }

    public func startRequest(onComplete: @escaping () -> Void) -> Bool {
        callbacks.append(onComplete)

        if !isRunningRequest {
            isRunningRequest = true
        }

        return isRunningRequest
    }
}
