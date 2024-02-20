@testable import CioInternalCommon
@testable import CioMessagingPush
import Foundation

public struct PushNotificationStub: PushNotification {
    public var pushId: String
    public var deliveryDate: Date?
    public var title: String
    public var body: String
    public var data: [AnyHashable: Any]
    public var attachments: [CioMessagingPush.PushAttachment] = []

    public static func getPushSentFromCIO(title: String = .random, body: String = .random, deliveryId: String = .random, deviceToken: String = .random, deepLink: String? = nil, imageUrl: String? = nil) -> PushNotificationStub {
        let pushId: String = .random // When CIO sends a push via APN or FCM, a push id will be randomly generated. So, we also randomly generate it in our test push notifications, too.

        let givenRichPushPayload: [AnyHashable: Any] = [
            "CIO-Delivery-ID": deliveryId,
            "CIO-Delivery-Token": deviceToken,
            "CIO": [
                "push": [
                    "link": deepLink,
                    "image": imageUrl
                ]
            ]
        ]

        return PushNotificationStub(pushId: pushId, deliveryDate: Date(), title: title, body: body, data: givenRichPushPayload)
    }

    public static func getPushNotSentFromCIO(title: String = .random, body: String = .random, payload: [AnyHashable: Any] = [:]) -> PushNotificationStub {
        let pushId: String = .random // When push sent via APN or FCM, a push id will be randomly generated. So, we also randomly generate it in our test push notifications, too.

        return PushNotificationStub(pushId: pushId, deliveryDate: Date(), title: title, body: body, data: payload)
    }

    public static func getLocalPush(pushId: String, title: String = .random, body: String = .random, payload: [AnyHashable: Any] = [:]) -> PushNotificationStub {
        // A local push will always have it's ID defined by the developer who constructs the push. So, the pushId could be hard-coded and not unique.
        // The OS populates the delivery date for local pushes.
        let deliveryDate = Date()

        return PushNotificationStub(pushId: pushId, deliveryDate: deliveryDate, title: title, body: body, data: payload)
    }
}
