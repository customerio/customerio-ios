import Foundation

internal protocol QueueQueryRunner: AutoMockable {
    func getNextTask(_ queue: [QueueTaskMetadata], lastFailedTask: QueueTaskMetadata?) -> QueueTaskMetadata?
}

// sourcery: InjectRegister = "QueueQueryRunner"
internal class CioQueueQueryRunner: QueueQueryRunner {
    private var queryCriteria = QueueQueryCriteria()

    func getNextTask(_ queue: [QueueTaskMetadata], lastFailedTask: QueueTaskMetadata?) -> QueueTaskMetadata? {
        guard !queue.isEmpty else {
            return nil
        }

        guard let lastFailedTask = lastFailedTask else {
            return queue[0]
        }

        updateCriteria(lastFailedTask: lastFailedTask)

        return queue.first(where: { doesTaskPassCriteria($0) })
    }

    private func updateCriteria(lastFailedTask: QueueTaskMetadata) {
        if let groupToExclude = lastFailedTask.groupStart {
            queryCriteria.excludeGroups.insert(groupToExclude)
        }
    }

    private func doesTaskPassCriteria(_ task: QueueTaskMetadata) -> Bool {
        var didPassCriteria = true

        if let groupsTaskBelongsTo = task.groupMember {
            queryCriteria.excludeGroups.forEach { groupToExclude in
                if groupsTaskBelongsTo.contains(groupToExclude) {
                    didPassCriteria = false
                }
            }
        }

        return didPassCriteria
    }
}

struct QueueQueryCriteria {
    var excludeGroups: Set<String> = Set()
}
