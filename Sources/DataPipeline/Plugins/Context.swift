import CioInternalCommon
import Segment

/// Plugin class that update the context properties in the request payload
class Context: Plugin {
    public let type = PluginType.before
    public weak var analytics: Analytics?

    public var deviceToken: String?
    public var attributes: [String: Any] = [:]

    let userAgentUtil: UserAgentUtil

    public var autoTrackDeviceAttributes: Bool

    public required init(autoTrackDeviceAttributes: Bool, diGraph: DIGraphShared) {
        self.autoTrackDeviceAttributes = autoTrackDeviceAttributes
        self.userAgentUtil = diGraph.userAgentUtil
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

            // remove library from context
            context.removeValue(forKey: "library")

            // if autoTrackDeviceAttributes is false, remove all device attributes except token and type which other destination might depend on
            if let device = context[keyPath: "device"] as? [String: Any] {
                if !autoTrackDeviceAttributes {
                    // Keep only device.token and device.type, remove everything else
                    let token = device["token"]
                    let type = device["type"]
                    context["device"] = ["token": token, "type": type]
                }
            }

            workingEvent.context = try JSON(context)
        } catch {
            analytics?.reportInternalError(error)
        }
        return workingEvent
    }
}
