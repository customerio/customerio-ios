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
    -> ActivityConfiguration<CIOCountdownTimerAttributes>
{
    ActivityConfiguration(for: CIOCountdownTimerAttributes.self) { context in
        CountdownTimerBannerView(attributes: context.attributes, state: context.state)
            .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
            .activityBackgroundTint(
                context.attributes.branding.accentColor.flatMap(Color.init(hex:)) ?? .orange)
            .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                CIOBrandingView(branding: context.attributes.branding)
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

// MARK: - Banner

@available(iOS 17.2, *)
private struct CountdownTimerBannerView: View {
    let attributes: CIOCountdownTimerAttributes
    let state: CIOCountdownTimerAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            if let heroKey = attributes.heroImageKey {
                CIOAssetImage(key: heroKey)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    CIOBrandingView(branding: attributes.branding).frame(height: 14)
                    Spacer()
                }
                Text(attributes.title)
                    .font(.headline).foregroundColor(.white)
                CountdownView(state: state)
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
        if now >= state.targetDate, let expired = state.expiredMessage {
            Text(expired)
                .font(.subheadline.bold())
                .foregroundColor(.white)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.statusMessage)
                    .font(.caption).foregroundColor(.white.opacity(0.8))
                Text(timerInterval: now...state.targetDate, countsDown: true)
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
        if now >= state.targetDate {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        } else {
            Text(timerInterval: now...state.targetDate, countsDown: true)
                .font(.system(size: 10, weight: .bold)).monospacedDigit()
        }
    }
}
#endif
