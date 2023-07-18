import CioInternalCommon
import Foundation

internal protocol CleanupRepository: AutoMockable {
    func cleanup()
}

// sourcery: InjectRegister = "CleanupRepository"
internal class CioCleanupRepository: CleanupRepository {
    private let queueStorage: QueueStorage

    init(queueStorage: QueueStorage) {
        self.queueStorage = queueStorage
    }

    func cleanup() {
        _ = queueStorage.deleteExpired()
    }
}
