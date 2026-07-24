#if os(iOS)
import CioInternalCommon
import Foundation

#if canImport(AppIntents)
import AppIntents

/// App Intent that reports a Customer.io `opened` metric for the exact Live Activity delivery the
/// user tapped, then brings the app to the foreground.
///
/// This is the App-Intent alternative to the deep-link/`widgetURL` open-tracking path. Attach it to
/// your Live Activity's tap target in your widget, constructing it from the **current**
/// `ContentState`'s Customer.io metadata so the reported open matches the update on screen:
///
/// ```swift
/// Button(intent: CioLiveActivityOpenIntent(
///     deliveryId: context.state.cioMetadata?.deliveryId ?? "",
///     deliveryToken: context.state.cioMetadata?.deliveryToken ?? ""
/// )) {
///     LockScreenView(state: context.state)
/// }
/// .buttonStyle(.plain)
/// ```
///
/// Why this is more reliable than matching a deep link:
/// - The identity is taken from the same `ContentState` that renders the view, so the open is
///   attributed to the precise start/update currently displayed — no dependency on dictionary
///   iteration order or on a shared deep link.
/// - It carries the identity in the intent itself, so it needs no app-side observer lookup and
///   works even on a cold launch (the app was terminated). The tap *is* the attribution.
///
/// - Note: `LiveActivityIntent` runs `perform()` in the host app's process (iOS 17+). The metric is
///   posted onto the shared event bus, which the in-app DataPipeline consumes; the bus persists and
///   replays events, so a tap that runs before SDK init still reports once init completes.
@available(iOS 17.0, *)
public struct CioLiveActivityOpenIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Open Live Notification"

    /// Bring the app to the foreground when the activity is tapped.
    public static let openAppWhenRun = true

    /// Customer.io delivery id of the update currently displayed on the activity.
    @Parameter(title: "Delivery ID") public var deliveryId: String
    /// Customer.io delivery token of the update currently displayed on the activity.
    @Parameter(title: "Delivery Token") public var deliveryToken: String

    public init() {}

    public init(deliveryId: String, deliveryToken: String) {
        self.deliveryId = deliveryId
        self.deliveryToken = deliveryToken
    }

    public func perform() async throws -> some IntentResult {
        // Nothing to attribute (e.g. a locally-driven state with no CIO delivery) — no-op.
        guard !deliveryId.isEmpty else { return .result() }
        // Report `opened` through the same pipeline push/delivered uses: a TrackMetricEvent the
        // in-app DataPipeline consumes and turns into a "Report Delivery Event".
        DIGraphShared.shared.eventBusHandler.postEvent(
            TrackMetricEvent(
                deliveryID: deliveryId,
                event: Metric.opened.rawValue,
                deviceToken: deliveryToken
            )
        )
        return .result()
    }
}
#endif
#endif
