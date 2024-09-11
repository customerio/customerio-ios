import Foundation

extension Message: CustomStringConvertible {
    // Used for getting details about the Message object for sending to logs.
    //
    // We are logging the Gist campaign id as delivery id because we call it delivery id on our system.
    var describeForLogs: String {
        "id: \(messageId), queueId: \(queueId ?? "none"), deliveryId: \(gistProperties.campaignId ?? "none")"
    }

    // Provides string representation of Message object with all its properties for debugging purposes.
    public var description: String {
        "Message(messageId=\(messageId), instanceId=\(instanceId), priority=\(String(describing: priority)), queueId=\(String(describing: queueId)), properties=\(gistProperties))"
    }
}

extension GistProperties: CustomStringConvertible {
    // Provides string representation of GistProperties object with all its properties for debugging purposes.
    public var description: String {
        "GistProperties(routeRule=\(String(describing: routeRule)), elementId=\(String(describing: elementId)), deliveryId=\(String(describing: campaignId)), position=\(position), persistent=\(String(describing: persistent)))"
    }
}
