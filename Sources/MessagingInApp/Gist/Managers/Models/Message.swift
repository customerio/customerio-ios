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
    public let queueId: String? // used to uniquely identify an in-app message.
    public let priority: Int?
    public let messageId: String // the messageId refers to the template used to render. For non-HTML messages, that messageId is something like "welcome-demo"
    public private(set) var gistProperties: GistProperties

    var properties = [String: Any]()

    public init(messageId: String) {
        self.queueId = nil
        self.priority = nil
        self.gistProperties = GistProperties(routeRule: nil, elementId: nil, campaignId: nil, position: .center, persistent: false)
        self.messageId = messageId
    }

    init(queueId: String? = nil, priority: Int? = nil, messageId: String, properties: [String: Any]?) {
        self.queueId = queueId
        self.priority = priority
        self.gistProperties = GistProperties(routeRule: nil, elementId: nil, campaignId: nil, position: .center, persistent: false)
        self.messageId = messageId

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
        let engineRoute = EngineRoute(route: messageId)
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

    func doesHavePageRule() -> Bool {
        gistProperties.routeRule != nil
    }

    var cleanPageRule: String? {
        guard let routeRule = gistProperties.routeRule else {
            return nil
        }
        return routeRule.replacingOccurrences(of: "\\", with: "/")
    }

    /*
     The HTTP response to get messages formats the page rules as regex.

     You can expect to see the following options.
     1. In Fly, if you use "Contains", the page rule will be formatted as ^(.*home.*)$ where "home" is what is entered in as the page rule. No matter if wildcards are used before or after "home" in Fly, the pattern will always be formatted as ^(.*N.*)$
     2. In Fly, if you use "Equals", the page rule will be formatted as ^(home)$ where "home" is what is entered in as the page rule. If wildcards are entered, they will be included in the pattern. Example: "home*" will be formatted as ^(home.*)$

     You can also use "OR" in Fly.
     Example OR: `^(home)|(settings)$`, if "home" and "settings" are entered in as the page rule using equals.
     */
    func doesPageRuleMatch(route: String) -> Bool {
        guard let cleanRouteRule = cleanPageRule else {
            return false
        }

        if let regex = try? NSRegularExpression(pattern: cleanRouteRule) {
            let range = NSRange(location: 0, length: route.utf16.count)
            if regex.firstMatch(in: route, options: [], range: range) == nil {
                return false // exit early to not show the message since page rule doesnt match
            }
        } else {
            Logger.instance.info(message: "Problem processing route rule message regex: \(cleanRouteRule)")
            return false // exit early to not show the message since we cannot parse the page rule for message.
        }

        return true
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
