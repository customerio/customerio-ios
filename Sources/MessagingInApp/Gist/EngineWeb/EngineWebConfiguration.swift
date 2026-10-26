import Foundation

struct EngineWebConfiguration: Encodable {
    /// Nil when no site ID is set, so the encoded configuration leaves it out instead of sending an empty one.
    let siteId: String?
    /// Public `pk_` key, sent alongside the site ID.
    let key: String?
    let dataCenter: String
    let instanceId: String
    let endpoint: String
    let messageId: String
    let livePreview: Bool = false
    let properties: [String: AnyEncodable?]?
    let colorScheme: String?

    init(
        siteId: String?,
        key: String? = nil,
        dataCenter: String,
        instanceId: String,
        endpoint: String,
        messageId: String,
        properties: [String: AnyEncodable?]?,
        colorScheme: String? = nil
    ) {
        self.siteId = siteId.flatMap { $0.isEmpty ? nil : $0 }
        self.key = key
        self.dataCenter = dataCenter
        self.instanceId = instanceId
        self.endpoint = endpoint
        self.messageId = messageId
        self.properties = properties
        self.colorScheme = colorScheme
    }
}
