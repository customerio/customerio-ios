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
            .activityBackgroundTint(
                CIOLiveActivitiesTemplates.branding?.accentColor.flatMap(Color.init(hex:)) ?? .orange
            )
            .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                CIOBrandingView(appBranding: CIOLiveActivitiesTemplates.branding)
                    .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
                    .frame(height: 20)
                    .padding(.leading, 4)
            }
            DynamicIslandExpandedRegion(.center) {
                CountdownView(state: context.state)
            }
        } compactLeading: {
            Text(context.attributes.title)
                .font(.caption2.bold()).lineLimit(1)
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

// MARK: - Banner

@available(iOS 17.2, *)
private struct CountdownTimerBannerView: View {
    let attributes: CIOCountdownTimerAttributes
    let state: CIOCountdownTimerAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            if let image = attributes.image {
                CIOAssetImage(key: image)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if let header = attributes.header {
                        Text(header)
                            .font(.caption2).foregroundColor(.white.opacity(0.7))
                    } else {
                        CIOBrandingView(appBranding: CIOLiveActivitiesTemplates.branding).frame(height: 14)
                    }
                    Spacer()
                }
                Text(attributes.title)
                    .font(.headline).foregroundColor(.white)
                CountdownView(state: state)
                if let stale = state.staleMessage {
                    Text(stale)
                        .font(.caption2).foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Sub-views

@available(iOS 17.2, *)
private struct CountdownView: View {
    let state: CIOCountdownTimerAttributes.ContentState

    var body: some View {
        let now = Date()
        if now >= state.targetDate.value, let expired = state.expiredMessage {
            Text(expired)
                .font(.subheadline.bold())
                .foregroundColor(countdownStatusColor(state.statusColor, fallback: .white))
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.subtitle)
                    .font(.caption).foregroundColor(.white.opacity(0.8))
                Text(timerInterval: now ... state.targetDate.value, countsDown: true)
                    .font(.title2.bold()).monospacedDigit()
                    .foregroundColor(.white)
            }
        }
    }
}

@available(iOS 17.2, *)
private struct CountdownCompactView: View {
    let state: CIOCountdownTimerAttributes.ContentState

    var body: some View {
        let now = Date()
        if now >= state.targetDate.value {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(countdownStatusColor(state.statusColor, fallback: .white))
        } else {
            Text(timerInterval: now ... state.targetDate.value, countsDown: true)
                .font(.system(size: 10, weight: .bold)).monospacedDigit()
        }
    }
}
#endif
