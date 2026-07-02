#if os(iOS)
@preconcurrency import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Widget

@available(iOS 17.2, *)
public struct CIOLiveScoreLiveActivity: Widget {
    public init() {}
    public var body: some WidgetConfiguration { makeLiveScoreConfiguration() }
}

@available(iOS 18, *)
public struct CIOLiveScoreWatchLiveActivity: Widget {
    public init() {}
    public var body: some WidgetConfiguration {
        makeLiveScoreConfiguration().supplementalActivityFamilies([.small])
    }
}

// MARK: - Configuration

@available(iOS 17.2, *)
@MainActor
private func makeLiveScoreConfiguration() -> ActivityConfiguration<CIOLiveScoreAttributes> {
    ActivityConfiguration(for: CIOLiveScoreAttributes.self) { context in
        LiveScoreBannerView(attributes: context.attributes, state: context.state)
            .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
            .activityBackgroundTint(CIOLiveActivitiesTemplates.branding?.accentColor.flatMap(Color.init(hex:)) ?? .black)
            .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                LiveScoreTeamColumn(
                    team: context.attributes.homeTeam,
                    score: context.state.homeScore
                )
                .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
                .padding(.leading, 4)
            }
            DynamicIslandExpandedRegion(.trailing) {
                LiveScoreTeamColumn(
                    team: context.attributes.awayTeam,
                    score: context.state.awayScore
                )
                .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
                .padding(.trailing, 4)
            }
            DynamicIslandExpandedRegion(.bottom) {
                LiveScoreSubtitleView(state: context.state)
            }
        } compactLeading: {
            Text(liveScoreText(context.state.homeScore))
                .font(.caption.bold()).monospacedDigit()
        } compactTrailing: {
            Text(liveScoreText(context.state.awayScore))
                .font(.caption.bold()).monospacedDigit()
        } minimal: {
            Image(systemName: "sportscourt")
                .font(.system(size: 10))
        }
    }
}

@available(iOS 17.2, *)
private func liveScoreText(_ score: Int?) -> String {
    score.map(String.init) ?? "-"
}

@available(iOS 17.2, *)
private func liveScoreStatusColor(_ hex: String?, fallback: Color) -> Color {
    hex.flatMap(Color.init(hex:)) ?? fallback
}

// MARK: - Banner

@available(iOS 17.2, *)
private struct LiveScoreBannerView: View {
    let attributes: CIOLiveScoreAttributes
    let state: CIOLiveScoreAttributes.ContentState

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                if let image = attributes.image {
                    CIOAssetImage(key: image).frame(height: 16)
                } else {
                    CIOBrandingView(appBranding: CIOLiveActivitiesTemplates.branding).frame(height: 16)
                }
                Spacer()
                LiveScoreSubtitleView(state: state)
            }
            HStack(spacing: 0) {
                LiveScoreTeamColumn(team: attributes.homeTeam, score: state.homeScore)
                    .frame(maxWidth: .infinity)
                LiveScoreTeamColumn(team: attributes.awayTeam, score: state.awayScore)
                    .frame(maxWidth: .infinity)
            }
            if let stale = state.staleMessage {
                Text(stale)
                    .font(.caption2).foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .foregroundColor(.white)
    }
}

// MARK: - Sub-views

@available(iOS 17.2, *)
private struct LiveScoreTeamColumn: View {
    let team: CIOLiveScoreAttributes.Team
    let score: Int?

    private var initials: String {
        String(team.name.prefix(3)).uppercased()
    }

    var body: some View {
        VStack(spacing: 4) {
            if let logo = team.logo {
                CIOAssetImage(key: logo).frame(width: 32, height: 32)
            } else {
                Text(initials)
                    .font(.caption.bold())
                    .frame(width: 32, height: 32)
            }
            Text(team.name)
                .font(.caption.bold())
                .foregroundColor(.secondary)
            Text(liveScoreText(score))
                .font(.title.bold())
                .monospacedDigit()
        }
    }
}

@available(iOS 17.2, *)
private struct LiveScoreSubtitleView: View {
    let state: CIOLiveScoreAttributes.ContentState

    var body: some View {
        if let subtitle = state.subtitle {
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(liveScoreStatusColor(state.statusColor, fallback: .secondary))
        }
    }
}
#endif
