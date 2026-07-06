#if os(iOS)
@preconcurrency import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Widget

@available(iOS 17.2, *)
public struct CIOCountdownTimerLiveActivity: Widget {
    public init() {}
    public var body: some WidgetConfiguration { makeCountdownTimerConfiguration() }
}

// MARK: - Configuration

@available(iOS 17.2, *)
@MainActor
private func makeCountdownTimerConfiguration()
    -> ActivityConfiguration<CIOCountdownTimerAttributes> {
    ActivityConfiguration(for: CIOCountdownTimerAttributes.self) { context in
        CountdownTimerBannerView(attributes: context.attributes, state: context.state)
            .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
            .activityBackgroundTint(CIOTemplateStyle.background(fallback: .orange))
            .activitySystemActionForegroundColor(CIOTemplateStyle.text)
    } dynamicIsland: { context in
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                CIOBrandingView(appBranding: CIOLiveActivitiesTemplates.branding)
                    .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
                    .frame(height: 20)
                    .padding(.leading, 4)
            }
            DynamicIslandExpandedRegion(.trailing) {
                // Island renders on the system's black pill — keep the value light.
                countdownValue(context.state, color: .white, font: .title3.bold())
                    .padding(.trailing, 4)
            }
            DynamicIslandExpandedRegion(.bottom) {
                if Date() < context.state.targetDate.value {
                    Text(context.state.subtitle)
                        .font(.caption2).foregroundColor(.white.opacity(0.8))
                }
            }
        } compactLeading: {
            CIOBrandingView(appBranding: CIOLiveActivitiesTemplates.branding)
                .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
                .frame(width: 20, height: 20)
        } compactTrailing: {
            CountdownCompactView(state: context.state)
        } minimal: {
            CountdownCompactView(state: context.state)
        }
    }
}

@available(iOS 17.2, *)
private func countdownStatusColor(_ hex: String?, fallback: Color) -> Color {
    hex.flatMap(Color.init(hex:)) ?? fallback
}

/// The countdown value shown on the trailing edge: a live timer while running, or the
/// `expiredMessage` once `targetDate` has passed. The range is only built while `now` is
/// before the target, so it can never form an invalid (crashing) interval.
@available(iOS 17.2, *)
@ViewBuilder
private func countdownValue(
    _ state: CIOCountdownTimerAttributes.ContentState,
    color: Color,
    font: Font
) -> some View {
    let now = Date()
    if now < state.targetDate.value {
        Text(timerInterval: now ... state.targetDate.value, countsDown: true)
            .font(font).monospacedDigit()
            .foregroundColor(color)
    } else if let expired = state.expiredMessage {
        Text(expired)
            .font(font)
            .foregroundColor(countdownStatusColor(state.statusColor, fallback: color))
    }
}

// MARK: - Banner

@available(iOS 17.2, *)
private struct CountdownTimerBannerView: View {
    let attributes: CIOCountdownTimerAttributes
    let state: CIOCountdownTimerAttributes.ContentState

    private var isRunning: Bool { Date() < state.targetDate.value }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                CIOBrandingView(appBranding: CIOLiveActivitiesTemplates.branding, showsName: true)
                    .foregroundColor(CIOTemplateStyle.text)
                Text(attributes.title)
                    .font(.headline)
                    .foregroundColor(CIOTemplateStyle.text)
                // Status message only while counting down; the expired state shows just the message.
                if isRunning {
                    Text(state.subtitle)
                        .font(.subheadline)
                        .foregroundColor(CIOTemplateStyle.text.opacity(0.8))
                }
                if let stale = state.staleMessage {
                    Text(stale)
                        .font(.caption2).foregroundColor(CIOTemplateStyle.text.opacity(0.6))
                }
            }
            Spacer(minLength: 12)
            countdownValue(state, color: CIOTemplateStyle.text, font: .system(size: 26, weight: .heavy))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Sub-views

@available(iOS 17.2, *)
private struct CountdownCompactView: View {
    let state: CIOCountdownTimerAttributes.ContentState

    var body: some View {
        let now = Date()
        if now < state.targetDate.value {
            Text(timerInterval: now ... state.targetDate.value, countsDown: true)
                .font(.system(size: 12, weight: .bold)).monospacedDigit()
        } else if let expired = state.expiredMessage {
            Text(expired)
                .font(.system(size: 12, weight: .bold)).lineLimit(1)
        }
    }
}
#endif
