import Common
import Foundation

internal protocol CleanupRepository: AutoMockable {
    func cleanup()
}

// sourcery: InjectRegister = "CleanupRepository"
internal class CioCleanupRepository: CleanupRepository {
    private let queue: Queue

    init(queue: Queue) {
        self.queue = queue
    }

    func cleanup() {
        queue.deleteExpiredTasks()
    }
}
