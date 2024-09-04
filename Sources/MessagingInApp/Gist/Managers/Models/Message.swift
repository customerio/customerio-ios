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
    public let instanceId = UUID().uuidString.lowercased()
    public let queueId: String?
    public let priority: Int?
    public let messageId: String
    public let gistProperties: GistProperties

    var properties = [String: Any]()

    public var isEmbedded: Bool {
        gistProperties.elementId != nil
    }

    public init(
        queueId: String? = nil,
        priority: Int? = nil,
        messageId: String,
        properties: [String: Any]? = nil,
        gistProperties: GistProperties? = nil
    ) {
        self.queueId = queueId
        self.priority = priority
        self.messageId = messageId
        self.gistProperties = gistProperties ?? Message.parseGistProperties(from: properties)
        if let props = properties {
            self.properties = props
        }
    }

    public convenience init(messageId: String, properties: [String: Any]?) {
        self.init(
            queueId: properties?["queueId"] as? String,
            priority: properties?["priority"] as? Int,
            messageId: messageId,
            gistProperties: Message.parseGistProperties(from: properties?["gist"] as? [String: Any])
        )
    }

    private static func parseGistProperties(from gist: [String: Any]?) -> GistProperties {
        let defaultPosition = MessagePosition.center
        guard let gist = gist else {
            return GistProperties(routeRule: nil, elementId: nil, campaignId: nil, position: defaultPosition, persistent: false)
        }

        let position = (gist["position"] as? String).flatMap(MessagePosition.init) ?? defaultPosition
        let routeRule = gist["routeRuleApple"] as? String
        let elementId = gist["elementId"] as? String
        let campaignId = gist["campaignId"] as? String
        let persistent = gist["persistent"] as? Bool ?? false

        return GistProperties(
            routeRule: routeRule,
            elementId: elementId,
            campaignId: campaignId,
            position: position,
            persistent: persistent
        )
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

extension Message {
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

extension Message: Equatable, Hashable {
    public static func == (lhs: Message, rhs: Message) -> Bool {
        // The queueId is the single-source-of-truth as a unique identifier generated by the backend.
        if let lhsQueueId = lhs.queueId, let rhsQueueId = rhs.queueId {
            return lhsQueueId == rhsQueueId
        }

        // If the queueId is nil, we fallback to the instanceId which is a unique ID generated client-side
        return lhs.instanceId == rhs.instanceId
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(instanceId)
        hasher.combine(queueId)
        hasher.combine(priority)
        hasher.combine(messageId)
    }
}
