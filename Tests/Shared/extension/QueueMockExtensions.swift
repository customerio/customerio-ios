import CioInternalCommon
@testable import CioTracking
import Foundation

public extension QueueMock {
    var deviceTokensDeleted: [String] {
        addTaskReceivedInvocations.map {
            ($0.data.value as? DeletePushNotificationQueueTaskData)?.deviceToken
        }.mapNonNil()
    }
}
