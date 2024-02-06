@testable import CioInternalCommon
import Foundation

public extension QueueStorage {
    func filterTrackEvents(_ type: QueueTaskType) -> [QueueTaskMetadata] {
        getInventory().filter { $0.taskType == type.rawValue }
    }
}
