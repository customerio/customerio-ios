import Foundation

struct EngineWebConfiguration: Encodable {
    let siteId: String
    let dataCenter: String
    let instanceId: String
    let endpoint: String
    let messageId: String
    let livePreview: Bool = false
    let properties: [String: AnyEncodable?]?
    let colorScheme: String?

    init(
        siteId: String,
        dataCenter: String,
        instanceId: String,
        endpoint: String,
        messageId: String,
        properties: [String: AnyEncodable?]?,
        colorScheme: String? = nil
    ) {
        self.siteId = siteId
        self.dataCenter = dataCenter
        self.instanceId = instanceId
        self.endpoint = endpoint
        self.messageId = messageId
        self.properties = properties
        self.colorScheme = colorScheme
    }
}
