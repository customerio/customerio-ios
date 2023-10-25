@testable import CioInternalCommon
@testable import CioTracking
import Foundation

public extension QueueStorage {
    func filterTrackEvents(_ type: QueueTaskType) -> [QueueTaskMetadata] {
        getInventory().filter { $0.taskType == type.rawValue }
    }
}
