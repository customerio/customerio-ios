import CioInternalCommon
import Foundation
#if canImport(UserNotifications)
import UserNotifications

/**
 The content of a push notification. Single source of truth for getting properties of a push notification.
 */
public class CustomerIOParsedPushPayload {
    public static let cioAttachmentsPrefix = "cio_sdk_"

    public var title: String {
        get {
            mutableNotificationContent.title
        }
        set {
            mutableNotificationContent.title = newValue
        }
    }

    public var body: String {
        get {
            mutableNotificationContent.body
        }
        set {
            mutableNotificationContent.body = newValue
        }
    }

    public var deepLink: URL? {
        get {
            cio?.push.link?.url
        }
        set {
            cioPush = cioPush?.linkSet(newValue?.absoluteString)
        }
    }

    public var image: URL? {
        get {
            cio?.push.image?.url
        }
        set {
            cioPush = cioPush?.imageSet(newValue?.absoluteString)
        }
    }

    public let deliveryId: String

    public let deviceToken: String

    public var cioAttachments: [UNNotificationAttachment] {
        mutableNotificationContent.attachments.filter { $0.identifier.starts(with: Self.cioAttachmentsPrefix) }
    }

    public func addImage(localFilePath: URL) {
        guard let imageAttachment =
            try? UNNotificationAttachment(
                identifier: "\(Self.cioAttachmentsPrefix)\(String.random)",
                url: localFilePath,
                options: nil
            )
        else {
            return
        }

        var existingAttachments = mutableNotificationContent.attachments
        existingAttachments.append(imageAttachment)

        mutableNotificationContent.attachments = existingAttachments
    }

    // This can be nil if a simple push instead of rich
    private var cio: CioRichPushPayload? {
        get {
            if let cioPushDictionary = mutableNotificationContent.userInfo["CIO"] as? [AnyHashable: Any] {
                return jsonAdapter.fromDictionary(cioPushDictionary)
            }

            return nil
        }
        set {
            // assert we have a valid payload before we set it as the new value
            guard let newUserInfo = jsonAdapter.toDictionary(newValue) else {
                return
            }
            mutableNotificationContent.userInfo["CIO"] = newUserInfo
        }
    }

    private var cioPush: CioRichPushPayload.Push? {
        get {
            cio?.push
        }
        set {
            if let newValue = newValue {
                cio = CioRichPushPayload(push: newValue)
            }
        }
    }

    private let jsonAdapter: JsonAdapter
    public let mutableNotificationContent: UNMutableNotificationContent
    public let notificationContent: UNNotificationContent

    public static func parse(
        pushNotification: PushNotification,
        jsonAdapter: JsonAdapter
    ) -> CustomerIOParsedPushPayload? {
        parse(notificationContent: pushNotification.rawNotification.request.content, jsonAdapter: jsonAdapter)
    }

    public static func parse(
        response: UNNotificationResponse,
        jsonAdapter: JsonAdapter
    ) -> CustomerIOParsedPushPayload? {
        parse(notificationContent: response.notification.request.content, jsonAdapter: jsonAdapter)
    }

    public static func parse(
        notificationContent: UNNotificationContent,
        jsonAdapter: JsonAdapter
    ) -> CustomerIOParsedPushPayload? {
        let raw = notificationContent.userInfo

        // If these fields are not present, then this push did not get sent by CIO. Exit early.
        guard let deliveryId = raw["CIO-Delivery-ID"] as? String,
              let deviceToken = raw["CIO-Delivery-Token"] as? String
        else {
            return nil
        }

        // Safely get a mutable instance of notification content. We expect this will be
        // successful, but to be runtime safe, we will return nil if this fails.
        guard let mutableNotificationContent = notificationContent.mutableCopy() as? UNMutableNotificationContent else {
            return nil
        }

        return CustomerIOParsedPushPayload(
            deliveryId: deliveryId,
            deviceToken: deviceToken,
            originalNotificationContent: notificationContent,
            mutableNotificationContent: mutableNotificationContent,
            jsonAdapter: jsonAdapter
        )
    }

    // Used when modifying push content before showing and for parsing after displaying.
    private init(
        deliveryId: String,
        deviceToken: String,
        originalNotificationContent: UNNotificationContent,
        mutableNotificationContent: UNMutableNotificationContent,
        jsonAdapter: JsonAdapter
    ) {
        self.deliveryId = deliveryId
        self.deviceToken = deviceToken
        self.notificationContent = originalNotificationContent
        self.mutableNotificationContent = mutableNotificationContent

        self.jsonAdapter = jsonAdapter
    }
}
#endif

struct CioRichPushPayload: Codable {
    let push: Push

    struct Push: Codable, AutoLenses {
        let link: String?
        let image: String?

        enum CodingKeys: String, CodingKey {
            case link
            case image
        }
    }

    enum CodingKeys: String, CodingKey {
        case push
    }
}
