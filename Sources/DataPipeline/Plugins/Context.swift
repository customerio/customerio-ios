import CioAnalytics
import CioInternalCommon

/// Plugin class that update the context properties in the request payload
class Context: Plugin {
    public let type = PluginType.before
    public weak var analytics: Analytics?

    public var deviceToken: String?
    public var attributes: [String: Any] = [:]

    let userAgentUtil: UserAgentUtil

    public required init(diGraph: DIGraphShared) {
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

            // Our push logic is currently hardcoded against ios
            // this is the current mitigation to ensure push notification
            // works for visionos till the backend handles "visionos"
            if context[keyPath: "device.type"] as? String == "visionos" {
                context[keyPath: "device.type"] = "ios"
            }

            // set the user agent
            context["userAgent"] = userAgentUtil.getUserAgentHeaderValue()

            // Remove analytics library information from context
            // CIO SDK information is being sent through user-agent
            context.removeValue(forKey: "library")

            workingEvent.context = try JSON(context)
        } catch {
            analytics?.reportInternalError(error)
        }
        return workingEvent
    }
}
