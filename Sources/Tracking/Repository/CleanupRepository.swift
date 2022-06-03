import Common
import Foundation

internal protocol CleanupRepository: AutoMockable {
    func cleanup()
}

// sourcery: InjectRegister = "CleanupRepository"
internal class CioCleanupRepository: CleanupRepository {
    private let queue: Queue

    init(diCommon: DICommon) {
        self.queue = diCommon.queue
    }

    func cleanup() {
        queue.deleteExpiredTasks()
    }
}
