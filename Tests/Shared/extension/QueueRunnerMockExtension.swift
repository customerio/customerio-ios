@testable import CioInternalCommon
import Foundation

public extension QueueRunnerMock {
    func setupRunAllTasksSuccessfully() {
        runTaskClosure = { _, onComplete in
            onComplete(.success(()))
        }
    }

    func setupRunAllTasksFailure() {
        runTaskClosure = { _, onComplete in
            // Choose an error that does not run certain logic in the code-base such as
            // HTTP requests being paused.
            onComplete(.failure(.getGenericFailure()))
        }
    }
}
