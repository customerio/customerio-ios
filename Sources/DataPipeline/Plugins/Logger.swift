import CioAnalytics
import CioInternalCommon

/// Logger plugin for logging all requests sent to analytics
class ConsoleLogger: Plugin {
    public let type = PluginType.after
    public weak var analytics: Analytics?

    private let logger: Logger

    public required init(diGraph: DIGraphShared) {
        self.logger = diGraph.logger
    }

    public func execute<T: RawEvent>(event: T?) -> T? {
        if let message = event?.toString() {
            logger.debug(message)
        }
        return event
    }
}
