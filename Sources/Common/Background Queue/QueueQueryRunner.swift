import Foundation

internal protocol QueueQueryRunner: AutoMockable {
    func getNextTask(_ queue: [QueueTaskMetadata], lastFailedTask: QueueTaskMetadata?) -> QueueTaskMetadata?
    func reset()
}

// sourcery: InjectRegister = "QueueQueryRunner"
internal class CioQueueQueryRunner: QueueQueryRunner {
    private var queryCriteria = QueueQueryCriteria()

    private let logger: Logger

    init(logger: Logger) {
        self.logger = logger
    }

    func getNextTask(_ queue: [QueueTaskMetadata], lastFailedTask: QueueTaskMetadata?) -> QueueTaskMetadata? {
        guard !queue.isEmpty else {
            return nil
        }
        if let lastFailedTask = lastFailedTask {
            updateCriteria(lastFailedTask: lastFailedTask)
        }

        // log *after* updating the criteria
        logger.debug("queue querying next task. criteria: \(queryCriteria)")

        return queue.first(where: { doesTaskPassCriteria($0) })
    }

    func reset() {
        logger.debug("resetting queue tasks query criteria")

        queryCriteria.reset()
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

    mutating func reset() {
        excludeGroups.removeAll()
    }
}
