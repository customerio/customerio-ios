import CioInternalCommon
import Foundation

// sourcery: InjectRegister = "CleanupRepository"
class CioCleanupRepository: CleanupRepository {
    private let queue: Queue

    init(queue: Queue) {
        self.queue = queue
    }

    func cleanup() {
        queue.deleteExpiredTasks()
    }
}
