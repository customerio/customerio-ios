import CioInternalCommon
import Segment

/// Plugin class that adds device attributes to Segment requests
class DeviceAttributes: Plugin {
    public let type = PluginType.before
    public weak var analytics: Analytics?

    public var token: String?
    public var attributes: [String: Any]?

    public required init() {}

    public func execute<T: RawEvent>(event: T?) -> T? {
        guard var workingEvent = event,
              var context = workingEvent.context?.dictionaryValue
        else { return event }

        do {
            let bgToken = context[keyPath: "device.token"] as? String
            if let token = token, bgToken == nil {
                context[keyPath: "device.token"] = token
                workingEvent.context = try JSON(context)
            }
            if let attributes = attributes {
                if let device = context[keyPath: "device"] as? [String: Any] {
                    context["device"] = device.mergeWith(attributes)
                } else {
                    context["device"] = attributes
                }
                workingEvent.context = try JSON(context)
            }
        } catch {
            analytics?.reportInternalError(error)
        }
        return workingEvent
    }
}
