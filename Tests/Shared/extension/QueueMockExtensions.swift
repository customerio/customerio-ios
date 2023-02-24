@testable import CioTracking
import Common
import Foundation

public extension QueueMock {
    var deviceTokensDeleted: [String] {
        addTaskReceivedInvocations.map {
            ($0.data.value as? DeletePushNotificationQueueTaskData)?.deviceToken
        }.mapNonNil()
    }

    var addTaskReturnValue: ModifyQueueResult {
        get { fatalError("this is a setter only property") }
        set {
            addTaskClosure = { _, _, _, _, onComplete in
                onComplete(newValue)
            }
        }
    }
}
