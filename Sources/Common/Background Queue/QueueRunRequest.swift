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
    private let queryRunner: QueueQueryRunner

    private let shortTaskId: (String) -> String = { $0[0 ..< 5] }

    init(
        runner: QueueRunner,
        storage: QueueStorage,
        requestManager: QueueRequestManager,
        logger: Logger,
        queryRunner: QueueQueryRunner
    ) {
        self.runner = runner
        self.storage = storage
        self.requestManager = requestManager
        self.logger = logger
        self.queryRunner = queryRunner
    }

    public func start(onComplete: @escaping () -> Void) {
        let isRequestCurrentlyRunning = requestManager.startRequest(onComplete: onComplete)

        if !isRequestCurrentlyRunning {
            startNewRequestRun()
        }
    }

    private func startNewRequestRun() {
        let inventory = storage.getInventory()

        runTasks(queueInventory: inventory, queryTotalNumberTasks: inventory.count)
    }

    // Disable swiftlint because function at this time isn't too complex to need to make it smaller.
    // Many of the lines of this function are logging related.
    // swiftlint:disable:next function_body_length
    private func runTasks(
        queueInventory: [QueueTaskMetadata],
        queryTotalNumberTasks: Int,
        lastFailedTask: QueueTaskMetadata? = nil
    ) {
        guard let nextTaskToRunInventoryItem = queryRunner.getNextTask(queueInventory, lastFailedTask: lastFailedTask)
        else {
            // we hit the end of the current inventory. Done!
            logger.debug("queue out of tasks to run.")

            queryRunner.reset()

            return requestManager.requestComplete()
        }

        let nextTaskStorageId = nextTaskToRunInventoryItem.taskPersistedId
        guard let nextTaskToRun = storage.get(storageId: nextTaskStorageId) else {
            // log error. this scenario shouldn't happen where task can't be found.
            logger.error("Tried to get queue task with storage id: \(nextTaskStorageId), but storage couldn't find it.")

            // The task failed to execute like a HTTP failure. Update `lastFailedTask`.
            return goToNextTask(queueInventory: queueInventory, queryTotalNumberTasks: queryTotalNumberTasks,
                                lastFailedTask: nextTaskToRunInventoryItem)
        }

        logger.debug("queue tasks left to run: \(queueInventory.count) out of \(queryTotalNumberTasks)")
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
                _ = self.storage.delete(storageId: nextTaskToRunInventoryItem.taskPersistedId)

                return self.goToNextTask(queueInventory: queueInventory, queryTotalNumberTasks: queryTotalNumberTasks,
                                         lastFailedTask: nil)
            case .failure(let error):
                self.logger
                    .debug("queue task \(self.shortTaskId(nextTaskStorageId)) run failed \(error.localizedDescription)")

                let previousRunResults = nextTaskToRun.runResults

                // When a HTTP request isn't made, dont update the run history to give us inaccurate data.
                if case .requestsPaused = error {
                    self.logger.debug("""
                    queue task \(self.shortTaskId(nextTaskStorageId)) didn't run because all HTTP requests paused.
                    """)

                    self.logger.info("queue is quitting early because all HTTP requests are paused.")
                    return self.goToNextTask(queueInventory: [], queryTotalNumberTasks: queryTotalNumberTasks,
                                             lastFailedTask: nil)
                } else {
                    let newRunResults = previousRunResults.totalRunsSet(previousRunResults.totalRuns + 1)

                    self.logger.debug("""
                    queue task \(self.shortTaskId(nextTaskStorageId)) updating run history
                    from: \(nextTaskToRun.runResults) to: \(newRunResults)
                    """)

                    _ = self.storage.update(storageId: nextTaskToRunInventoryItem.taskPersistedId,
                                            runResults: newRunResults)
                }

                return self.goToNextTask(queueInventory: queueInventory, queryTotalNumberTasks: queryTotalNumberTasks,
                                         lastFailedTask: nextTaskToRunInventoryItem)
            }
        }
    }

    private func goToNextTask(
        queueInventory: [QueueTaskMetadata],
        queryTotalNumberTasks: Int,
        lastFailedTask: QueueTaskMetadata?
    ) {
        var newInventory = queueInventory
        newInventory.removeFirst()
        runTasks(queueInventory: newInventory, queryTotalNumberTasks: queryTotalNumberTasks,
                 lastFailedTask: lastFailedTask)
    }
}
