import Foundation

public protocol QueueRunRequest: AutoMockable {
    func start(onComplete: @escaping () -> Void)
}

// Logic of the queue data structure. Queries for tasks to run and executes each task one-by-one.
// sourcery: InjectRegister = "QueueRunRequest"
public class CioQueueRunRequest: QueueRunRequest {
    private let runner: QueueRunner
    private let storage: QueueStorage
    private let requestManager: QueueRequestManager
    private let logger: Logger

    private let shortTaskId: (String) -> String = { $0[0 ..< 5] }

    init(runner: QueueRunner, storage: QueueStorage, requestManger: QueueRequestManager, logger: Logger) {
        self.runner = runner
        self.storage = storage
        self.requestManager = requestManger
        self.logger = logger
    }

    public func start(onComplete: @escaping () -> Void) {
        let isRequestCurrentlyRunning = requestManager.startRequest(onComplete: onComplete)

        if !isRequestCurrentlyRunning {
            startNewRequestRun()
        }
    }

    private func startNewRequestRun() {
        let inventory = storage.getInventory()

        runTasks(query: inventory, queryTotalNumberTasks: inventory.count)
    }

    private func runTasks(query: [QueueTaskMetadata], queryTotalNumberTasks: Int) {
        if query.isEmpty { // we hit the end of the current inventory. Done!
            logger.debug("queue out of tasks to run.")
            requestManager.requestComplete()
            return
        }

        let nextTaskToRunInventoryItem = query[0]
        let nextTaskStorageId = nextTaskToRunInventoryItem.taskPersistedId
        guard let nextTaskToRun = storage.get(storageId: nextTaskStorageId) else {
            // log error. this scenario shouldn't happen where task can't be found.
            logger.error("Tried to get queue task with storage id: \(nextTaskStorageId), but storage couldn't find it.")

            // delete task from inventory since we can't find it in storage so we don't want to run it.
            // ignore result because if it's successful or not, all we can do is try and delete and move on.
            let success = storage.delete(storageId: nextTaskStorageId)
            logger.debug("deleted task \(nextTaskStorageId) success: \(success)")

            return goToNextTask(query: query, queryTotalNumberTasks: queryTotalNumberTasks)
        }

        logger.debug("queue tasks left to run: \(query.count) out of \(queryTotalNumberTasks)")
        logger.debug("""
        queue next task to run: \(shortTaskId(nextTaskStorageId)),
        \(nextTaskToRun.type), \(nextTaskToRun.data.string ?? ""), \(nextTaskToRun.runResults)
        """)

        // we are not using [weak self] because if the task is currently running,
        // we dont want the result handler to get garbage collected which could
        // make the task run again when it shouldn't.
        //
        // if we wanted to use [weak self] then we should allow running a task to cancel
        // while executing which would then allow this to use [weak self].
        runner.runTask(nextTaskToRun) { result in
            switch result {
            case .success:
                self.logger.debug("queue task \(self.shortTaskId(nextTaskStorageId)) ran successfully")

                self.logger.debug("queue deleting task \(self.shortTaskId(nextTaskStorageId))")
                let success = self.storage.delete(storageId: nextTaskToRunInventoryItem.taskPersistedId)
                self.logger.debug("queue deleting task \(self.shortTaskId(nextTaskStorageId)) success: \(success)")
            case .failure(let error):
                self.logger
                    .debug("queue task \(self.shortTaskId(nextTaskStorageId)) fail - \(error.localizedDescription)")

                let executedTaskPreviousRunResults = nextTaskToRun.runResults
                let newRunResults = executedTaskPreviousRunResults
                    .totalRunsSet(executedTaskPreviousRunResults.totalRuns + 1)

                self.logger.debug("""
                queue task \(self.shortTaskId(nextTaskStorageId)) updating run history
                from: \(nextTaskToRun.runResults) to: \(newRunResults)
                """)

                let success = self.storage.update(storageId: nextTaskToRunInventoryItem.taskPersistedId,
                                                  runResults: newRunResults)
                self.logger.debug("queue task \(self.shortTaskId(nextTaskStorageId)) update success \(success)")
            }

            return self.goToNextTask(query: query, queryTotalNumberTasks: queryTotalNumberTasks)
        }
    }

    private func goToNextTask(query: [QueueTaskMetadata], queryTotalNumberTasks: Int) {
        var newQuery = query
        newQuery.removeFirst()
        runTasks(query: newQuery, queryTotalNumberTasks: queryTotalNumberTasks)
    }
}
