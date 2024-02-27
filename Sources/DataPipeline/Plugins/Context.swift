import CioInternalCommon
import Segment

/// Plugin class that update the context properties in the request payload
class Context: Plugin {
    public let type = PluginType.before
    public weak var analytics: Analytics?

    public var deviceToken: String?
    public var attributes: [String: Any] = [:]

    var userAgentUtil: UserAgentUtil {
        DIGraphShared.shared.userAgentUtil
    }

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
            if let token = deviceToken, bgToken == nil {
                context[keyPath: "device.token"] = token
                workingEvent.context = try JSON(context)
            }

            // set the user agent
            context["userAgent"] = userAgentUtil.getUserAgentHeaderValue()

            // set the device attributes
            if let device = context[keyPath: "device"] as? [String: Any], autoTrackDeviceAttributes {
                context["device"] = device.mergeWith(attributes)
            } else {
                context["device"] = attributes
            }
            workingEvent.context = try JSON(context)
        } catch {
            analytics?.reportInternalError(error)
        }
        return workingEvent
    }
}
