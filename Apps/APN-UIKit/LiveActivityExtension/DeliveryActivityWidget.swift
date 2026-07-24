#if os(iOS)
import ActivityKit
import CioLiveActivities
import CioLiveActivities_Attributes
import SwiftUI
import WidgetKit

// MARK: - Widget

/// Renders `DeliveryActivityAttributes` on the Lock Screen and in the Dynamic Island.
///
/// This is entirely app-owned SwiftUI — the Customer.io SDK never renders Live Activities. A
/// customer writes exactly this kind of `Widget` for their own attributes type. It uses only
/// SF Symbols, so it is fully self-contained (no bundled image assets).
@available(iOS 16.2, *)
struct DeliveryActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DeliveryActivityAttributes.self) { context in
            lockScreen(context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "shippingbox.fill")
                        .font(.title2)
                        .foregroundStyle(context.state.accentColor)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    arrivalView(context.state.estimatedArrival)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.title).font(.headline)
                        DeliveryProgressBar(state: context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(context.state.accentColor)
            } compactTrailing: {
                arrivalView(context.state.estimatedArrival)
                    .font(.caption2)
            } minimal: {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(context.state.accentColor)
            }
            .widgetURL(context.state.cioMetadata?.deepLink.flatMap(URL.init(string:)))
        }
    }

    /// Lock Screen presentation. On iOS 17+ the whole surface is an `App Intent` tap target that
    /// reports the Customer.io `opened` for the exact delivery on screen (no deep link needed);
    /// on iOS 16.x it falls back to the `widgetURL` deep-link path.
    @ViewBuilder
    private func lockScreen(_ context: ActivityViewContext<DeliveryActivityAttributes>) -> some View {
        let content = DeliveryLockScreenView(attributes: context.attributes, state: context.state)
            .activityBackgroundTint(Color.black.opacity(0.85))
            .activitySystemActionForegroundColor(.white)
        if #available(iOS 17.0, *) {
            Button(intent: CioLiveActivityOpenIntent(
                deliveryId: context.state.cioMetadata?.deliveryId ?? "",
                deliveryToken: context.state.cioMetadata?.deliveryToken ?? ""
            )) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content.widgetURL(context.state.cioMetadata?.deepLink.flatMap(URL.init(string:)))
        }
    }

    /// A live countdown when arrival is in the future, otherwise the arrival clock time.
    @ViewBuilder
    private func arrivalView(_ arrival: EpochSecondsDate?) -> some View {
        if let date = arrival?.date {
            if date > Date() {
                Text(timerInterval: Date() ... date, countsDown: true)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            } else {
                Text(date, style: .time)
            }
        }
    }
}

// MARK: - Lock Screen

@available(iOS 16.2, *)
private struct DeliveryLockScreenView: View {
    let attributes: DeliveryActivityAttributes
    let state: DeliveryActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 34))
                .foregroundStyle(state.accentColor)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 6) {
                Text(attributes.orderNumber)
                    .font(.caption).foregroundStyle(.secondary)
                Text(state.title)
                    .font(.headline)
                if let subtitle = state.subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                DeliveryProgressBar(state: state)
            }

            if let date = state.estimatedArrival?.date, date > Date() {
                VStack(spacing: 2) {
                    Text("ETA").font(.caption2).foregroundStyle(.secondary)
                    Text(timerInterval: Date() ... date, countsDown: true)
                        .font(.callout.bold()).monospacedDigit()
                        .frame(width: 62)
                }
            }
        }
        .padding()
    }
}

// MARK: - Progress bar

@available(iOS 16.2, *)
private struct DeliveryProgressBar: View {
    let state: DeliveryActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ProgressView(value: state.progress.fraction)
                .tint(state.accentColor)
            Text("Step \(state.progress.current) of \(state.progress.total)")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Helpers

@available(iOS 16.2, *)
private extension DeliveryActivityAttributes.ContentState {
    /// Status accent color from the optional hex string, falling back to the app tint.
    var accentColor: Color {
        statusColor.flatMap(Color.init(hex:)) ?? .green
    }
}

private extension Color {
    /// Parse `"#RRGGBB"` / `"RRGGBB"`; returns `nil` for anything malformed.
    init?(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
#endif
