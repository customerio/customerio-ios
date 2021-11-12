import Foundation

public protocol QueueRunRequest: AutoMockable {
    func start(onComplete: @escaping () -> Void)
}

// sourcery: InjectRegister = "QueueRunRequest"
public class CioQueueRunRequest: QueueRunRequest {
    private let runner: QueueRunner
    private let storage: QueueStorage
    private let requestManger: QueueRequestManager
    private let logger: Logger

    init(runner: QueueRunner, storage: QueueStorage, requestManger: QueueRequestManager, logger: Logger) {
        self.runner = runner
        self.storage = storage
        self.requestManger = requestManger
        self.logger = logger
    }

    public func start(onComplete: @escaping () -> Void) {
        let isRequestCurrentlyRunning = requestManger.startRequest(onComplete: onComplete)

        if !isRequestCurrentlyRunning {
            startNewRequestRun()
        }
    }

    private func startNewRequestRun() {
        let inventory = storage.getInventory()

        runTasks(query: inventory)
    }

    private func runTasks(query: [QueueTaskMetadata]) {
        let goToNextTask: () -> Void = {
            var newQuery = query
            newQuery.removeFirst()
            self.runTasks(query: newQuery)
        }

        if query.isEmpty { // we hit the end of the current inventory. Done!
            logger.verbose("background queue out of tasks.")

            requestManger.requestComplete()

            return
        }

        let nextTaskToRunInventoryItem = query[0]
        let nextTaskStorageId = nextTaskToRunInventoryItem.taskPersistedId
        guard let nextTaskToRun = storage.get(storageId: nextTaskStorageId) else {
            // delete task from inventory since we can't find it in storage so we don't want to run it.
            // ignore result because if it's successful or not, all we can do is try and delete and move on.
            _ = storage.delete(storageId: nextTaskStorageId)

            // log error. this scenario shouldn't happen where task can't be found.
            logger.error("Tried to get queue task with storage id: \(nextTaskStorageId), but storage couldn't find it.")

            return goToNextTask()
        }

        logger
            .verbose("background queue next task \(nextTaskStorageId). query tasks remaining: \(query.count)")
        logger.debug("next background queue task to run: \(nextTaskToRunInventoryItem) => \(nextTaskToRun)")

        // we are not using [weak self] because if the task is currently running,
        // we dont want the result handler to get garbage collected which could
        // make the task run again when it shouldn't.
        //
        // if we wanted to use [weak self] then we should allow running a task to cancel
        // while executing which would then allow this to use [weak self].
        runner.runTask(nextTaskToRun) { result in
            switch result {
            case .success:
                self.logger.verbose("background queue task \(nextTaskStorageId) success")

                _ = self.storage.delete(storageId: nextTaskToRunInventoryItem.taskPersistedId)
            case .failure(let error):
                self.logger.verbose("background queue task \(nextTaskStorageId) fail - \(error.localizedDescription)")

                let executedTaskPreviousRunResults = nextTaskToRun.runResults
                let newRunResults = executedTaskPreviousRunResults
                    .totalRunsSet(executedTaskPreviousRunResults.totalRuns + 1)

                _ = self.storage.update(storageId: nextTaskToRunInventoryItem.taskPersistedId,
                                        runResults: newRunResults)
            }

            return goToNextTask()
        }
    }
}
