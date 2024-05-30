import Foundation

public class GistProperties {
    public let routeRule: String?
    public let elementId: String?
    public let campaignId: String?
    public let position: MessagePosition
    public let persistent: Bool?

    init(routeRule: String?, elementId: String?, campaignId: String?, position: MessagePosition, persistent: Bool?) {
        self.routeRule = routeRule
        self.elementId = elementId
        self.position = position
        self.campaignId = campaignId
        self.persistent = persistent
    }
}

public class Message {
    public private(set) var instanceId = UUID().uuidString.lowercased()
    public let id: String? // Uniquely identify an in-app message. This ID is also known as the "queue id" in Gist.
    public let priority: Int?
    public let templateId: String // Refers to the template used to render. Also known as "message id" in Gist. For non-HTML messages, this value is something like "welcome-demo".
    public private(set) var gistProperties: GistProperties

    var properties = [String: Any]()

    public init(templateId: String) {
        self.id = nil
        self.priority = nil
        self.gistProperties = GistProperties(routeRule: nil, elementId: nil, campaignId: nil, position: .center, persistent: false)
        self.templateId = templateId
    }

    // Used to construct instance from API response
    init(queueId: String? = nil, priority: Int? = nil, messageId: String, properties: [String: Any]?) {
        self.id = queueId
        self.priority = priority
        self.gistProperties = GistProperties(routeRule: nil, elementId: nil, campaignId: nil, position: .center, persistent: false)
        self.templateId = messageId

        if let properties = properties {
            self.properties = properties
            if let gist = self.properties["gist"] as? [String: Any] {
                var messagePosition = MessagePosition.center
                if let position = gist["position"] as? String,
                   let positionValue = MessagePosition(rawValue: position) {
                    messagePosition = positionValue
                }
                var routeRule: String?
                if let routeRuleApple = gist["routeRuleApple"] as? String {
                    routeRule = routeRuleApple
                }
                var elementId: String?
                if let elementIdValue = gist["elementId"] as? String {
                    elementId = elementIdValue
                }
                var campaignId: String?
                if let campaignIdValue = gist["campaignId"] as? String {
                    campaignId = campaignIdValue
                }
                var persistent = false
                if let persistentValue = gist["persistent"] as? Bool {
                    persistent = persistentValue
                }

                self.gistProperties = GistProperties(
                    routeRule: routeRule,
                    elementId: elementId,
                    campaignId: campaignId,
                    position: messagePosition,
                    persistent: persistent
                )
            }
        }
    }

    public func addProperty(key: String, value: Any) {
        properties[key] = AnyEncodable(value)
    }

    func toEngineRoute() -> EngineRoute {
        let engineRoute = EngineRoute(route: templateId)
        properties.keys.forEach { key in
            if let value = properties[key] {
                engineRoute.addProperty(key: key, value: value)
            }
        }
        return engineRoute
    }
}

// Convenient functions for Inline message feature
extension Message {
    var elementId: String? {
        gistProperties.elementId
    }

    var isInlineMessage: Bool {
        elementId != nil
    }

    var isModalMessage: Bool {
        !isInlineMessage
    }
}

// Messages come with a priority used to determine the order of which messages should show in the app.
// Given a list of Messages that could be displayed, sort them by priority (lower values have higher priority).
extension Array where Element == Message {
    func sortByMessagePriority() -> [Message] {
        sorted {
            switch ($0.priority, $1.priority) {
            case (let priority0?, let priority1?):
                // Both messages have a priority, so we compare them.
                return priority0 < priority1
            case (nil, _):
                // The first message has no priority, it should be considered greater so that it ends up at the end of the sorted array.
                return false
            case (_, nil):
                // The second message has no priority, the first message should be ordered first.
                return true
            }
        }
    }
}
