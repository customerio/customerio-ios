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

// The Live Activity + Dynamic Island DSL (expanded/compact/minimal regions) makes this a single
// long-but-flat declarative body; splitting it would obscure the layout rather than clarify it.
// swiftlint:disable function_body_length
@available(iOS 17.2, *)
@MainActor
private func makeLiveScoreConfiguration() -> ActivityConfiguration<CIOLiveScoreAttributes> {
    ActivityConfiguration(for: CIOLiveScoreAttributes.self) { context in
        LiveScoreBannerView(attributes: context.attributes, state: context.state)
            .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
            .activityBackgroundTint(liveScoreBackgroundColor)
            .activitySystemActionForegroundColor(liveScoreTextColor)
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
            if liveScoreHasScore(context.state) {
                HStack(spacing: 3) {
                    LiveScoreCrest(team: context.attributes.homeTeam, size: 18)
                        .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
                    Text(liveScoreText(context.state.homeScore))
                        .font(.caption.bold()).monospacedDigit()
                }
            } else {
                liveScoreLeagueMark(context.attributes.image)
                    .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
            }
        } compactTrailing: {
            if liveScoreHasScore(context.state) {
                HStack(spacing: 3) {
                    Text(liveScoreText(context.state.awayScore))
                        .font(.caption.bold()).monospacedDigit()
                    LiveScoreCrest(team: context.attributes.awayTeam, size: 18)
                        .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
                }
            } else if let subtitle = context.state.subtitle {
                Text(subtitle).font(.caption2).lineLimit(1)
            }
        } minimal: {
            liveScoreLeagueMark(context.attributes.image)
                .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
        }
    }
}

// swiftlint:enable function_body_length

@available(iOS 17.2, *)
private func liveScoreText(_ score: Int?) -> String {
    score.map(String.init) ?? "-"
}

@available(iOS 17.2, *)
private func liveScoreStatusColor(_ hex: String?, fallback: Color) -> Color {
    hex.flatMap(Color.init(hex:)) ?? fallback
}

@available(iOS 17.2, *)
private func liveScoreHasScore(_ state: CIOLiveScoreAttributes.ContentState) -> Bool {
    state.homeScore != nil || state.awayScore != nil
}

@available(iOS 17.2, *)
private var liveScoreBackgroundColor: Color { CIOTemplateStyle.background(fallback: .black) }

@available(iOS 17.2, *)
private var liveScoreTextColor: Color { CIOTemplateStyle.text }

/// The league / broadcaster mark used in the center of the banner and the compact island.
/// Falls back to a system symbol when no `image` asset is configured.
@available(iOS 17.2, *)
@ViewBuilder
private func liveScoreLeagueMark(_ imageKey: String?) -> some View {
    if let imageKey {
        CIOAssetImage(key: imageKey)
            .frame(width: 18, height: 18)
    } else {
        Image(systemName: "sportscourt")
            .font(.system(size: 10))
    }
}

// MARK: - Banner

@available(iOS 17.2, *)
private struct LiveScoreBannerView: View {
    let attributes: CIOLiveScoreAttributes
    let state: CIOLiveScoreAttributes.ContentState

    var body: some View {
        VStack(spacing: 8) {
            // Scores row: [home crest][home score] · center mark · [away score][away crest]
            HStack(spacing: 10) {
                if attributes.homeTeam.logo != nil {
                    LiveScoreCrest(team: attributes.homeTeam)
                }
                Text(liveScoreText(state.homeScore))
                    .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                Spacer(minLength: 6)
                liveScoreCenterMark
                Spacer(minLength: 6)
                Text(liveScoreText(state.awayScore))
                    .font(.system(size: 34, weight: .heavy)).monospacedDigit()
                if attributes.awayTeam.logo != nil {
                    LiveScoreCrest(team: attributes.awayTeam)
                }
            }
            // Team names under each side.
            HStack {
                Text(attributes.homeTeam.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(attributes.awayTeam.name)
                    .font(.subheadline.weight(.semibold))
            }
            // Status line, centered at the bottom.
            LiveScoreSubtitleView(state: state)
            if let stale = state.staleMessage {
                Text(stale)
                    .font(.caption2).foregroundColor(liveScoreTextColor.opacity(0.6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .foregroundColor(liveScoreTextColor)
    }

    @ViewBuilder private var liveScoreCenterMark: some View {
        // The center mark is the league/broadcaster logo. When none is configured,
        // render nothing (the app brand is not a sensible scoreboard center).
        if let image = attributes.image {
            CIOAssetImage(key: image).frame(height: 24)
        }
    }
}

// MARK: - Sub-views

/// A team crest on a white disc, falling back to the team-name initials when no logo resolves.
@available(iOS 17.2, *)
private struct LiveScoreCrest: View {
    let team: CIOLiveScoreAttributes.Team
    var size: CGFloat = 40

    private var initials: String { String(team.name.prefix(3)).uppercased() }

    var body: some View {
        ZStack {
            Circle().fill(Color.white)
            if let logo = team.logo {
                CIOAssetImage(key: logo).padding(size * 0.12)
            } else {
                Text(initials)
                    .font(.system(size: size * 0.3, weight: .bold))
                    .foregroundColor(.black)
            }
        }
        .frame(width: size, height: size)
    }
}

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
