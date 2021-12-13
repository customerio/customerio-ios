import Foundation

internal protocol QueueQueryRunner: AutoMockable {
    func getNextTask(_ queue: [QueueTaskMetadata], lastFailedTask: QueueTaskMetadata?) -> QueueTaskMetadata?
}

// sourcery: InjectRegister = "QueueQueryRunner"
internal class CioQueueQueryRunner: QueueQueryRunner {
    func getNextTask(_ queue: [QueueTaskMetadata], lastFailedTask: QueueTaskMetadata?) -> QueueTaskMetadata? {
        guard !queue.isEmpty else {
            return nil
        }

        guard let lastFailedTask = lastFailedTask else {
            return queue[0]
        }

        let criteria = getCriteria(lastFailedTask: lastFailedTask)

        return queue.first(where: { doesTaskPassCriteria($0, criteria: criteria) })
    }

    private func getCriteria(lastFailedTask: QueueTaskMetadata) -> QueueQueryCriteria {
        var criteria = QueueQueryCriteria(excludeGroups: nil)

        if let groupsToExclude = lastFailedTask.groupsParent {
            criteria = criteria.excludeGroupsSet(groupsToExclude)
        }

        return criteria
    }

    private func doesTaskPassCriteria(_ task: QueueTaskMetadata, criteria: QueueQueryCriteria) -> Bool {
        var didPassCriteria = true

        if let groupsTaskBelongsTo = task.groupsChild {
            criteria.excludeGroups?.forEach { groupToExclude in
                if groupsTaskBelongsTo.contains(groupToExclude) {
                    didPassCriteria = false
                }
            }
        }

        return didPassCriteria
    }
}

struct QueueQueryCriteria: AutoLenses {
    let excludeGroups: [String]?
}
