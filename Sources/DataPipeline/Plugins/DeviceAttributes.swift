import CioInternalCommon
import Segment

/// Plugin class that adds device attributes to Segment requests
class DeviceAttributes: Plugin {
    public let type = PluginType.before
    public weak var analytics: Analytics?

    public var token: String?
    public var attributes: [String: Any]?

    public var autoTrackDeviceAttributes: Bool

    public required init(autoTrackDeviceAttributes: Bool) {
        self.autoTrackDeviceAttributes = autoTrackDeviceAttributes
    }

    public func execute<T: RawEvent>(event: T?) -> T? {
        guard var workingEvent = event,
              var context = workingEvent.context?.dictionaryValue
        else { return event }

        do {
            // **Background queue migration safeguard:**
            //
            // This fetches the device token from the context.device.token, and casts the value as string
            // Value of token is fed from `processRegisterDeviceFromBGQ` method.
            let bgToken = context[keyPath: "device.token"] as? String
            // Prevents unexpected token overwriting in this method
            // maintaining effective working during background queue migration.
            // This check does not affect non-background queue migration calls or direct CDP calls
            if let token = token, bgToken == nil {
                context[keyPath: "device.token"] = token
                workingEvent.context = try JSON(context)
            }
            if let attributes = attributes {
                if let device = context[keyPath: "device"] as? [String: Any], autoTrackDeviceAttributes {
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
