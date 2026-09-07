import CioInternalCommon
import Foundation

/// Decides which SDK records reach the file.
///
/// The sink captures every record the SDK emits, and on a device that is overwhelmingly not what a
/// geofence drive needs. Measured across seven real captures: one idle simulator run was 23,136
/// records and 12.9 MB, of which 22,544 records (94%) were in-app polling, against nine geofence
/// records — 0.03%. Unfiltered, a background test session fills a device with traffic nobody will
/// ever read.
///
/// The predicate is a **deny-list**, not an allow-list: a module we have not met yet keeps being
/// recorded rather than silently disappearing. Two rules protect against the deny-list being wrong —
/// errors are never dropped, and anything that mentions location vocabulary is kept whatever else
/// matches it.
///
/// Measured effect over eight captures: 26,646 records to 896, 14.3 MB to 361 KB, with **zero** of
/// the 235 location-bearing records lost.
enum DiagnosticFilter {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var enabled = true
    private nonisolated(unsafe) static var dropped: Int = 0

    /// Runtime switch, off the Location test screen. Turning the filter off records everything,
    /// which is what you want when the bug is in a module the deny-list removes.
    static var isEnabled: Bool {
        get { lock.withLock { enabled } }
        set { lock.withLock { enabled = newValue } }
    }

    /// Records dropped since launch, so a reader can tell "quiet" from "filtered".
    static var droppedCount: Int { lock.withLock { dropped } }

    /// Modules whose entire output is noise for a location drive.
    private static let denyTags: Set<String> = ["InApp", "CIO-Inbox", "SSE", "Polling"]

    /// Untagged records, matched on how the message opens. The second element, where present, must
    /// also appear in the message — it narrows prefixes too generic to match on alone (`Found `
    /// would otherwise swallow anything).
    private static let denyUntagged: [(prefix: String, required: String?)] = [
        // In-app redux store. Narrowed rather than a bare `Store:` so an unrelated future store is
        // not swallowed silently.
        ("Store: action:", nil),
        ("Store: state ", nil),
        ("Store: no state changes", nil),
        ("Store: ", "InAppMessagingState"),
        // CDP/Segment event envelopes. iOS logs these bare; Android prefixes them with prose, so
        // both shapes are listed — otherwise the same payload is dropped on one platform and kept
        // on the other, which is how the one outbound location body survived by accident.
        ("{\"", nil),
        ("Customer.io Data Pipelines running {", nil),
        ("processing event on", nil),
        ("applying base attributes", nil),
        ("SegmentStartupQueue", nil),
        ("Analytics starting", nil),
        ("track a screen", nil),
        ("automatic screenview ignored", nil),
        ("Fetched Settings:", nil),
        // Gist / in-app fetch loop.
        ("Gist:", nil),
        ("Gist queue fetch", nil),
        ("Current gist route", nil),
        ("X-CIO-Use-SSE", nil),
        ("Action received:", nil),
        ("Unhandled action received:", nil),
        ("No state changes", nil),
        ("Fetching user messages", nil),
        ("Found ", "in-app messages"),
        ("Found ", "inbox messages"),
        ("Processing ", "regular messages"),
        ("Saved ", "anonymous messages"),
        ("Retrieved ", "anonymous messages"),
        ("No anonymous messages", nil),
        ("Cleared all anonymous", nil),
        // Event-bus wiring. The largest single block left after the first pass — 21% of everything
        // that survived. `Posting event` is deliberately absent: it is the only place the raw fix
        // the SDK acted on appears (`LocationAcquiredEvent(… latitude … longitude …)`).
        ("CombinedCacheEventBusHandler: Adding observer", nil),
        ("CombinedCacheEventBusHandler: Replaying event", nil),
        ("CombinedCacheEventBusHandler: No observers", nil)
    ]

    /// Evaluated **before** the deny rules. Anything speaking location vocabulary is kept no matter
    /// what else would have matched it.
    ///
    /// Measured cost against the current deny-list: zero records, zero bytes — every one of these is
    /// already kept. It is insurance, and the reason to add it now rather than after something is
    /// lost: the next person to add a deny pattern does not have to reason about whether it clips a
    /// geofence record.
    private static let locationKeep: NSRegularExpression? = try? NSRegularExpression(
        pattern: "geofen|region|latitud|longitud|coordinat|CLLocation|fence|dwell|radius|"
            + "geo_|boundary|monitor|lat=|lng=|LocationAcquired",
        options: [.caseInsensitive]
    )

    static func shouldRecord(
        src: DiagnosticLog.Source,
        tag: String?,
        level: CioLogLevel,
        message: String
    ) -> Bool {
        let keep = evaluate(src: src, tag: tag, level: level, message: message)
        if !keep { lock.withLock { dropped += 1 } }
        return keep
    }

    private static func evaluate(
        src: DiagnosticLog.Source,
        tag: String?,
        level: CioLogLevel,
        message: String
    ) -> Bool {
        guard isEnabled else { return true }
        // A filter must never be the reason a failure went unseen.
        if level == .error { return true }
        // The app's own records are the session spine — a handful per run, and the only thing
        // marking process starts and device-state changes.
        if src == .app { return true }
        if let regex = locationKeep {
            let range = NSRange(message.startIndex ..< message.endIndex, in: message)
            if regex.firstMatch(in: message, options: [], range: range) != nil { return true }
        }
        if let tag { return !denyTags.contains(tag) }
        return !denyUntagged.contains { prefix, required in
            message.hasPrefix(prefix) && (required.map(message.contains) ?? true)
        }
    }

    /// Written into the file header. A filtered file is otherwise silently lossy — nothing in it
    /// distinguishes "in-app was quiet" from "in-app was removed", and a reader would draw the wrong
    /// conclusion from its absence.
    static func headerJSON() -> String {
        let tags = denyTags.sorted().map { "\"\($0)\"" }.joined(separator: ",")
        return "{\"enabled\":\(isEnabled),\"denyTags\":[\(tags)],\"denyUntaggedPatterns\":\(denyUntagged.count)}"
    }
}
