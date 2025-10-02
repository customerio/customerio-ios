import CioInternalCommon
import Foundation

/// Represents the frequency control for anonymous (broadcast) messages.
/// Controls how often and when a message can be shown to anonymous users.
class BroadcastFrequency {
    /// Number of times to show the message. 0 = unlimited, >0 = max times to show
    let count: Int
    /// Delay in seconds between shows
    let delay: Int
    /// If true, show message even after user dismisses it
    let ignoreDismiss: Bool

    /// Returns true if frequency has a count limit (count > 0)
    var isEmpty: Bool {
        count == 0
    }

    init(count: Int, delay: Int, ignoreDismiss: Bool = false) {
        self.count = count
        self.delay = delay
        self.ignoreDismiss = ignoreDismiss
    }
}

/// Represents properties specific to anonymous (broadcast) messages.
class BroadcastProperties {
    let frequency: BroadcastFrequency

    init(frequency: BroadcastFrequency) {
        self.frequency = frequency
    }
}

public class GistProperties {
    public let routeRule: String?
    public let elementId: String?
    public let campaignId: String?
    public let position: MessagePosition
    public let persistent: Bool?
    public let overlayColor: String?
    /// If present, this is an anonymous (broadcast) message
    let broadcast: BroadcastProperties?

    init(
        routeRule: String?,
        elementId: String?,
        campaignId: String?,
        position: MessagePosition,
        persistent: Bool?,
        overlayColor: String?,
        broadcast: BroadcastProperties? = nil
    ) {
        self.routeRule = routeRule
        self.elementId = elementId
        self.position = position
        self.campaignId = campaignId
        self.persistent = persistent
        self.overlayColor = overlayColor
        self.broadcast = broadcast
    }
}

public class Message {
    let instanceId = UUID().uuidString.lowercased()
    let queueId: String?
    let priority: Int?
    let messageId: String
    let gistProperties: GistProperties
    let properties: [String: Any]

    public var isEmbedded: Bool {
        gistProperties.elementId != nil
    }

    public var elementId: String? {
        gistProperties.elementId
    }

    /// Returns true if this is an anonymous (broadcast) message
    var isAnonymousMessage: Bool {
        gistProperties.broadcast != nil
    }

    public init(
        messageId: String,
        queueId: String? = nil,
        priority: Int? = nil,
        properties: [String: Any]?
    ) {
        self.messageId = messageId
        self.queueId = queueId
        self.priority = priority
        self.gistProperties = Message.parseGistProperties(from: properties?["gist"] as? [String: Any], messageId: messageId, queueId: queueId)
        self.properties = properties ?? [:]
    }

    private static func parseGistProperties(from gist: [String: Any]?, messageId: String, queueId: String?) -> GistProperties {
        let defaultPosition = MessagePosition.center
        guard let gist = gist else {
            return GistProperties(routeRule: nil, elementId: nil, campaignId: nil, position: defaultPosition, persistent: false, overlayColor: nil, broadcast: nil)
        }

        let position = (gist["position"] as? String).flatMap(MessagePosition.init) ?? defaultPosition
        let routeRule = gist["routeRuleApple"] as? String
        let elementId = gist["elementId"] as? String
        let campaignId = gist["campaignId"] as? String
        let persistent = gist["persistent"] as? Bool ?? false
        let overlayColor = gist["overlayColor"] as? String
        let broadcast = parseBroadcastProperties(from: gist["broadcast"] as? [String: Any], messageId: messageId, queueId: queueId)

        return GistProperties(
            routeRule: routeRule,
            elementId: elementId,
            campaignId: campaignId,
            position: position,
            persistent: persistent,
            overlayColor: overlayColor,
            broadcast: broadcast
        )
    }

    private static func parseBroadcastProperties(from broadcast: [String: Any]?, messageId: String, queueId: String?) -> BroadcastProperties? {
        guard let broadcast = broadcast,
              let frequencyDict = broadcast["frequency"] as? [String: Any]
        else {
            return nil
        }

        // Count and delay are required - no defaults
        guard let count = frequencyDict["count"] as? Int,
              let delay = frequencyDict["delay"] as? Int
        else {
            DIGraphShared.shared.logger.debug("Skipping anonymous message frequency parsing due to missing count or delay for messageId=\(messageId) queueId=\(queueId ?? "nil")")
            return nil
        }

        // Defensive validation: reject negative values
        guard count >= 0, delay >= 0 else {
            DIGraphShared.shared.logger.debug("Skipping anonymous message frequency parsing due to negative count or delay for messageId=\(messageId) queueId=\(queueId ?? "nil")")
            return nil
        }

        let ignoreDismiss = frequencyDict["ignoreDismiss"] as? Bool ?? false
        let frequency = BroadcastFrequency(count: count, delay: delay, ignoreDismiss: ignoreDismiss)
        return BroadcastProperties(frequency: frequency)
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
            DIGraphShared.shared.logger.logWithModuleTag("Problem processing route rule message regex: \(cleanRouteRule)", level: .info)
            return false // exit early to not show the message since we cannot parse the page rule for message.
        }

        return true
    }

    func messageMatchesRoute(_ currentRoute: String?) -> Bool {
        if doesHavePageRule() {
            guard let currentRoute else { return false }
            return doesPageRuleMatch(route: currentRoute)
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
