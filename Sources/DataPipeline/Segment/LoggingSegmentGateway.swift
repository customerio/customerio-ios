import CioAnalytics
import CioInternalCommon
import Foundation

/// Logs every call (`DataPipelineLogTail`), then passes it to `gateway`, with only what the call
/// itself carries: the event, a userId the call names, a device token the call sets, and the
/// top-level values of its properties or traits (`p.<key>`). What Segment fills in when it processes
/// the event (its userId and anonymousId, the `Context` plugin's token, the timestamp) is never read
/// here, so a line shows no value the call doesn't carry. Nothing is built while the log is off.
final class LoggingSegmentGateway: SegmentGateway {
    let gateway: SegmentGateway
    /// The SDK instance this gateway belongs to (`DataPipelineLogTail.instance`)
    private let instance = DataPipelineLogTail.instance

    init(gateway: SegmentGateway) {
        self.gateway = gateway
    }

    /// Logs in front of the gateway that passes to `analytics`.
    convenience init(analytics: Analytics) {
        self.init(gateway: AnalyticsSegmentGateway(analytics: analytics))
    }

    var userId: String? { gateway.userId }

    var anonymousId: String { gateway.anonymousId }

    func identify(userId: String, traits: [String: Any]?) {
        log("segment.identify", user: userId, values: Self.values(traits))
        gateway.identify(userId: userId, traits: traits)
    }

    func identify<T: Codable>(userId: String, traits: T?) {
        log("segment.identify", user: userId, values: Self.values(encoding: traits))
        gateway.identify(userId: userId, traits: traits)
    }

    func identify<T: Codable>(traits: T) {
        log("segment.identify", values: Self.values(encoding: traits))
        gateway.identify(traits: traits)
    }

    func track(name: String) {
        log("segment.track", event: name)
        gateway.track(name: name)
    }

    func track(name: String, properties: [String: Any]?) {
        log("segment.track", event: name, values: Self.values(properties))
        gateway.track(name: name, properties: properties)
    }

    func track<P: Codable>(name: String, properties: P?) {
        log("segment.track", event: name, values: Self.values(encoding: properties))
        gateway.track(name: name, properties: properties)
    }

    func track(name: String, properties: [String: Any]?, deviceToken: String) {
        log("segment.track", event: name, token: deviceToken, values: Self.values(properties))
        gateway.track(name: name, properties: properties, deviceToken: deviceToken)
    }

    func screen(title: String, category: String?) {
        log("segment.screen", event: title)
        gateway.screen(title: title, category: category)
    }

    func screen(title: String, category: String?, properties: [String: Any]?) {
        log("segment.screen", event: title, values: Self.values(properties))
        gateway.screen(title: title, category: category, properties: properties)
    }

    func screen<P: Codable>(title: String, category: String?, properties: P?) {
        log("segment.screen", event: title, values: Self.values(encoding: properties))
        gateway.screen(title: title, category: category, properties: properties)
    }

    func alias(newId: String) {
        log("segment.alias", user: newId)
        gateway.alias(newId: newId)
    }

    func reset() {
        log("segment.reset")
        gateway.reset()
    }

    /// An event the SDK built carries whatever the SDK set on it; the rest Segment fills in.
    func process(event: RawEvent) {
        log(
            Self.ev(of: event),
            event: (event as? TrackEvent)?.event ?? (event as? ScreenEvent)?.name,
            user: event.userId,
            anon: event.anonymousId,
            token: event.context?.dictionaryValue?[keyPath: "device.token"] as? String,
            values: Self.values(Self.payload(of: event)?.dictionaryValue)
        )
        gateway.process(event: event)
    }

    /// `values` is only built when the line is written: the log is off in most apps.
    private func log(
        _ ev: String,
        event: String? = nil,
        user: String? = nil,
        anon: String? = nil,
        token: String? = nil,
        values: @autoclosure () -> [(String, String)] = []
    ) {
        DataPipelineLogTail.handOff(ev, [
            ("sdk", String(instance)),
            ("event", event),
            ("user", user),
            ("anon", anon),
            ("token", token)
        ] + values().map { key, value -> (String, String?) in ("p.\(key)", value) })
    }

    private static func ev(of event: RawEvent) -> String {
        switch event {
        case is IdentifyEvent: return "segment.identify"
        case is ScreenEvent: return "segment.screen"
        case is AliasEvent: return "segment.alias"
        default: return "segment.track"
        }
    }

    private static func payload(of event: RawEvent) -> JSON? {
        switch event {
        case let track as TrackEvent: return track.properties
        case let screen as ScreenEvent: return screen.properties
        case let identify as IdentifyEvent: return identify.traits
        default: return nil
        }
    }

    /// The top-level strings, booleans and numbers of a call's properties or traits, by key. Nested
    /// objects and arrays are left out.
    private static func values(_ dictionary: [String: Any]?) -> [(String, String)] {
        (dictionary ?? [:]).compactMap { key, value in primitive(value).map { (key, $0) } }.sorted { $0.0 < $1.0 }
    }

    /// Codable properties or traits, encoded as Segment encodes them.
    private static func values<T: Codable>(encoding value: T?) -> [(String, String)] {
        guard let value, let json = try? JSON(with: value) else { return [] }
        return values(json.dictionaryValue)
    }

    private static func primitive(_ value: Any) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            // A boolean bridges to NSNumber too; only its CF type tells it from 0 and 1
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.stringValue
        default:
            return nil
        }
    }
}
