import CioAnalytics
import CioInternalCommon
import Foundation

/// The one way our SDK hands events to Segment, and reads back the identity Segment holds. Every
/// call is passed through unchanged; the gateway exists so each hand-off can be logged in one place
/// (`LoggingSegmentGateway`) and so tests can stand in for Segment. Plugin setup, flush and storage stay
/// on `Analytics`.
protocol SegmentGateway: AnyObject {
    /// Segment's userId.
    var userId: String? { get }

    /// Segment's anonymousId.
    var anonymousId: String { get }

    func identify(userId: String, traits: [String: Any]?)

    func identify<T: Codable>(userId: String, traits: T?)

    /// Traits for the current profile, without a userId.
    func identify<T: Codable>(traits: T)

    func track(name: String)

    func track(name: String, properties: [String: Any]?)

    func track<P: Codable>(name: String, properties: P?)

    /// Tracks an event that carries `deviceToken` itself, whatever token the `Context` plugin holds
    /// when Segment processes it.
    func track(name: String, properties: [String: Any]?, deviceToken: String)

    func screen(title: String, category: String?)

    func screen(title: String, category: String?, properties: [String: Any]?)

    func screen<P: Codable>(title: String, category: String?, properties: P?)

    func alias(newId: String)

    func reset()

    /// An event built by the SDK, handed to Segment as it is.
    func process(event: RawEvent)
}

/// Builds Segment and the gateway in front of it. Tests override it in the graph to hand off to a
/// stand-in.
struct SegmentFactory {
    let makeAnalytics: (Configuration) -> Analytics
    /// The gateway for an `Analytics`.
    let makeGateway: (Analytics) -> SegmentGateway

    static let live = SegmentFactory(
        makeAnalytics: { Analytics(configuration: $0) },
        makeGateway: { LoggingSegmentGateway(analytics: $0) }
    )
}

extension DIGraphShared {
    /// Hand-written: a factory of closures, overridden by tests.
    var segmentFactory: SegmentFactory {
        let overridden: SegmentFactory? = getOverriddenInstance()
        return overridden ?? .live
    }
}

/// Passes every call to `analytics` as it is.
final class AnalyticsSegmentGateway: SegmentGateway {
    let analytics: Analytics

    init(analytics: Analytics) {
        self.analytics = analytics
    }

    var userId: String? { analytics.userId }

    var anonymousId: String { analytics.anonymousId }

    func identify(userId: String, traits: [String: Any]?) {
        analytics.identify(userId: userId, traits: traits)
    }

    func identify<T: Codable>(userId: String, traits: T?) {
        analytics.identify(userId: userId, traits: traits)
    }

    func identify<T: Codable>(traits: T) {
        analytics.identify(traits: traits)
    }

    func track(name: String) {
        analytics.track(name: name)
    }

    func track(name: String, properties: [String: Any]?) {
        analytics.track(name: name, properties: properties)
    }

    func track<P: Codable>(name: String, properties: P?) {
        analytics.track(name: name, properties: properties)
    }

    func track(name: String, properties: [String: Any]?, deviceToken: String) {
        analytics.track(name: name, properties: properties, enrichments: [Context.deviceTokenEnrichment(deviceToken)])
    }

    func screen(title: String, category: String?) {
        analytics.screen(title: title, category: category)
    }

    func screen(title: String, category: String?, properties: [String: Any]?) {
        analytics.screen(title: title, category: category, properties: properties)
    }

    func screen<P: Codable>(title: String, category: String?, properties: P?) {
        analytics.screen(title: title, category: category, properties: properties)
    }

    func alias(newId: String) {
        analytics.alias(newId: newId)
    }

    func reset() {
        analytics.reset()
    }

    func process(event: RawEvent) {
        analytics.process(event: event)
    }
}
