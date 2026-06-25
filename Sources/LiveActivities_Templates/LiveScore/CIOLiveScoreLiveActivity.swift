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
            .activityBackgroundTint(.black)
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
                LiveScorePeriodView(state: context.state)
            }
        } compactLeading: {
            Text("\(context.state.homeScore)")
                .font(.caption.bold()).monospacedDigit()
        } compactTrailing: {
            Text("\(context.state.awayScore)")
                .font(.caption.bold()).monospacedDigit()
        } minimal: {
            Text("\(context.state.homeScore)-\(context.state.awayScore)")
                .font(.system(size: 10, weight: .bold)).monospacedDigit()
        }
    }
}

// MARK: - Banner

@available(iOS 17.2, *)
private struct LiveScoreBannerView: View {
    let attributes: CIOLiveScoreAttributes
    let state: CIOLiveScoreAttributes.ContentState

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                CIOBrandingView(branding: CIOActivityBranding(
                    name: attributes.sport,
                    logoKey: attributes.leagueLogoKey
                ))
                .frame(height: 16)
                Spacer()
                LiveScorePeriodView(state: state)
            }
            HStack(spacing: 0) {
                LiveScoreTeamColumn(team: attributes.homeTeam, score: state.homeScore)
                    .frame(maxWidth: .infinity)
                Text("vs")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(minWidth: 28)
                LiveScoreTeamColumn(team: attributes.awayTeam, score: state.awayScore)
                    .frame(maxWidth: .infinity)
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
    let score: Int

    var body: some View {
        VStack(spacing: 4) {
            if let logoKey = team.logoKey {
                CIOAssetImage(key: logoKey).frame(width: 32, height: 32)
            }
            Text(team.name)
                .font(.caption.bold())
                .foregroundColor(.secondary)
            Text("\(score)")
                .font(.title.bold())
                .monospacedDigit()
        }
    }
}

@available(iOS 17.2, *)
private struct LiveScorePeriodView: View {
    let state: CIOLiveScoreAttributes.ContentState

    var body: some View {
        VStack(spacing: 1) {
            if let message = state.statusMessage {
                Text(message).font(.caption2).foregroundColor(.secondary)
            } else {
                Text(state.period).font(.caption2).foregroundColor(.secondary)
                if let clock = state.clock {
                    Text(clock).font(.system(size: 9, weight: .semibold)).monospacedDigit()
                }
            }
        }
    }
}
#endif
