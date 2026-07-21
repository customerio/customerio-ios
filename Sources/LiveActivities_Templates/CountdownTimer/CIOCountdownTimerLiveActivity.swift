#if os(iOS)
import ActivityKit
import CioLiveActivities_Attributes
import SwiftUI
import WidgetKit

/// The Customer.io **Countdown Timer** Live Activity widget.
///
/// Add this to your widget extension's `WidgetBundle`, passing your app's
/// ``CIOCountdownTimerBranding``. It renders ``CIOCountdownTimerAttributes`` on the Lock Screen and
/// in the Dynamic Island, showing a live countdown to `endTime`, and wires the tap deep link from
/// the Customer.io push metadata:
///
/// ```swift
/// @main
/// struct MyWidgets: WidgetBundle {
///     var body: some Widget {
///         CIOCountdownTimerLiveActivity(branding: CIOCountdownTimerBranding(logo: Image("brand-logo")))
///     }
/// }
/// ```
@available(iOS 16.2, *)
public struct CIOCountdownTimerLiveActivity: Widget {
    private let branding: CIOCountdownTimerBranding

    /// `Widget` requires a no-argument initializer so WidgetKit can construct the type; this uses
    /// the default (dark) branding. Prefer ``init(branding:)`` from your `WidgetBundle` to style it.
    public init() {
        self.branding = CIOCountdownTimerBranding()
    }

    public init(branding: CIOCountdownTimerBranding) {
        self.branding = branding
    }

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: CIOCountdownTimerAttributes.self) { context in
            CountdownLockScreenView(attributes: context.attributes, state: context.state, branding: branding)
                .modifier(TemplateBackgroundModifier(background: branding.background))
                .widgetURL(context.state.cioMetadata?.deepLink.flatMap(URL.init(string:)))
        } dynamicIsland: { context in
            dynamicIsland(for: context)
        }
    }

    @available(iOS 16.2, *)
    private func dynamicIsland(for context: ActivityViewContext<CIOCountdownTimerAttributes>) -> DynamicIsland {
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                BrandLogo(logo: branding.logo, size: 24)
            }
            DynamicIslandExpandedRegion(.trailing) {
                CountdownText(endTime: context.state.endTime).font(.title3.bold()).monospacedDigit()
            }
            DynamicIslandExpandedRegion(.bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.title).font(.headline)
                    if let status = context.state.statusMessage {
                        Text(status).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        } compactLeading: {
            BrandLogo(logo: branding.logo, size: 18)
        } compactTrailing: {
            // A timer `Text` reserves a wide fixed slot in the Dynamic Island (so the pill doesn't
            // resize as digits tick), which otherwise stretches the compact pill full-width. Cap it
            // to an `MM:SS` width so the island hugs the camera.
            CountdownText(endTime: context.state.endTime)
                .font(.caption2).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                .frame(width: 44, alignment: .trailing)
        } minimal: {
            BrandLogo(logo: branding.logo, size: 20)
        }
        .widgetURL(context.state.cioMetadata?.deepLink.flatMap(URL.init(string:)))
    }
}

// MARK: - Lock Screen

@available(iOS 16.2, *)
private struct CountdownLockScreenView: View {
    let attributes: CIOCountdownTimerAttributes
    let state: CIOCountdownTimerAttributes.ContentState
    let branding: CIOCountdownTimerBranding

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                BrandLogo(logo: branding.logo, size: 22)
                Text(attributes.header).font(.subheadline)
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title).font(.title3.bold())
                    if let status = state.statusMessage {
                        Text(status).font(.subheadline).opacity(0.8)
                    }
                }
                Spacer(minLength: 12)
                CountdownText(endTime: state.endTime)
                    .font(.title.bold())
                    .monospacedDigit()
            }
        }
        .foregroundStyle(branding.textColor)
        .padding()
        // Read the whole card as one coherent VoiceOver element (header, title, status, and the time
        // remaining) instead of announcing the ticking timer digits on their own.
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Countdown

/// The live countdown to `endTime`. Uses the system timer clock with hours hidden, so it ticks
/// `MM:SS` (e.g. "59:17", "0:17") — compact and self-updating.
///
/// The `endTime > Date()` check runs once at render, not continuously: if the state is rendered with
/// a future `endTime` the clock ticks down and then **rests at "0:00"** (it does not disappear on
/// its own — the view isn't re-evaluated per second). The finished state appears when a push
/// delivers a new content-state (no `endTime` + a "done" `title`). Rendering nothing for an absent /
/// past `endTime` also avoids constructing an invalid `timerInterval` range.
@available(iOS 16.2, *)
private struct CountdownText: View {
    let endTime: EpochSecondsDate?

    var body: some View {
        // Capture `now` once: using it for both the guard and the range's lower bound
        // avoids an invalid `now ... date` interval if `endTime` elapses between the
        // two reads (Text(timerInterval:) requires lowerBound <= upperBound).
        let now = Date()
        if let date = endTime?.date, date > now {
            Text(timerInterval: now ... date, countsDown: true, showsHours: false)
                .multilineTextAlignment(.trailing)
        }
    }
}
#endif
