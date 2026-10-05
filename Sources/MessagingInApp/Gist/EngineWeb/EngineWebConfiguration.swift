import Foundation

struct EngineWebConfiguration: Encodable {
    let siteId: String
    /// Public `wk_` key, so the renderer loads messages with `?key=` instead of the site ID.
    let key: String?
    let dataCenter: String
    let instanceId: String
    let endpoint: String
    let messageId: String
    let livePreview: Bool = false
    let properties: [String: AnyEncodable?]?
    let colorScheme: String?

    init(
        siteId: String,
        key: String? = nil,
        dataCenter: String,
        instanceId: String,
        endpoint: String,
        messageId: String,
        properties: [String: AnyEncodable?]?,
        colorScheme: String? = nil
    ) {
        self.siteId = siteId
        self.key = key
        self.dataCenter = dataCenter
        self.instanceId = instanceId
        self.endpoint = endpoint
        self.messageId = messageId
        self.properties = properties
        self.colorScheme = colorScheme
    }
}
