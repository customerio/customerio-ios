#if os(iOS)
@preconcurrency import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Widget

@available(iOS 17.2, *)
public struct CIOAuctionBidLiveActivity: Widget {
    public init() {}
    public var body: some WidgetConfiguration { makeAuctionBidConfiguration() }
}

// MARK: - Configuration

@available(iOS 17.2, *)
@MainActor
private func makeAuctionBidConfiguration()
    -> ActivityConfiguration<CIOAuctionBidAttributes> {
    ActivityConfiguration(for: CIOAuctionBidAttributes.self) { context in
        AuctionBidBannerView(attributes: context.attributes, state: context.state)
            .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
            .activityBackgroundTint(CIOTemplateStyle.background(fallback: Color(red: 0.12, green: 0.08, blue: 0.20)))
            .activitySystemActionForegroundColor(CIOTemplateStyle.text)
            .widgetURL(context.state.cioMetadata?.deepLink.flatMap(URL.init(string:)))
    } dynamicIsland: { context in
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                CIOBrandingView(appBranding: CIOLiveActivitiesTemplates.branding)
                    .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
                    .frame(height: 20)
                    .padding(.leading, 4)
            }
            DynamicIslandExpandedRegion(.trailing) {
                // Island renders on the black pill — keep content light.
                auctionTrailing(context.state, color: .white)
                    .padding(.trailing, 4)
            }
            DynamicIslandExpandedRegion(.bottom) {
                HStack(spacing: 8) {
                    auctionBid(context.attributes, state: context.state)
                        .font(.headline.bold()).monospacedDigit()
                    Text(context.attributes.title)
                        .font(.caption).foregroundColor(.white.opacity(0.7)).lineLimit(1)
                    Spacer()
                }
            }
        } compactLeading: {
            CIOBrandingView(appBranding: CIOLiveActivitiesTemplates.branding)
                .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
                .frame(width: 20, height: 20)
        } compactTrailing: {
            auctionTrailing(context.state, color: .white)
        } minimal: {
            CIOBrandingView(appBranding: CIOLiveActivitiesTemplates.branding)
                .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
                .frame(width: 18, height: 18)
        }
    }
}

@available(iOS 17.2, *)
private func auctionStatusColor(_ hex: String?, fallback: Color) -> Color {
    hex.flatMap(Color.init(hex:)) ?? fallback
}

/// The "$1,250"-style bid amount as a single concatenated `Text` (so callers can style it).
@available(iOS 17.2, *)
private func auctionBid(_ attributes: CIOAuctionBidAttributes, state: CIOAuctionBidAttributes.ContentState) -> Text {
    Text(attributes.currencySymbol) + Text(state.currentBid)
}

/// Trailing value for the Dynamic Island: a live countdown while bidding, else the status.
/// The countdown range is only built before `endTime`, so it can't form an invalid interval.
@available(iOS 17.2, *)
@ViewBuilder
private func auctionTrailing(_ state: CIOAuctionBidAttributes.ContentState, color: Color) -> some View {
    if Date() < state.endTime.value {
        HStack(spacing: 2) {
            Image(systemName: "alarm").font(.system(size: 9))
            Text(timerInterval: Date() ... state.endTime.value, countsDown: true)
                .font(.system(size: 11, weight: .bold)).monospacedDigit()
        }
        .foregroundColor(color)
    } else {
        Text(state.statusMessage)
            .font(.system(size: 11, weight: .bold)).lineLimit(1)
            .foregroundColor(auctionStatusColor(state.statusColor, fallback: color))
    }
}

// MARK: - Banner

@available(iOS 17.2, *)
private struct AuctionBidBannerView: View {
    let attributes: CIOAuctionBidAttributes
    let state: CIOAuctionBidAttributes.ContentState

    private var isEnded: Bool { Date() >= state.endTime.value }
    private var statusColor: Color { auctionStatusColor(state.statusColor, fallback: CIOTemplateStyle.text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                CIOBrandingView(appBranding: CIOLiveActivitiesTemplates.branding, showsName: true)
                    .foregroundColor(CIOTemplateStyle.text)
                Spacer()
                // While bidding, the status sits top-right; once ended it becomes the headline.
                if !isEnded {
                    Text(state.statusMessage)
                        .font(.caption).foregroundColor(statusColor)
                }
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if isEnded {
                        Text(state.statusMessage)
                            .font(.title2.bold())
                            .foregroundColor(statusColor)
                        // Won-style detail (item + final price) shown when a result image is present;
                        // a bare outcome (e.g. "lost") sends no image and shows only the headline.
                        if attributes.image != nil {
                            HStack(spacing: 6) {
                                Text(attributes.title)
                                    .foregroundColor(CIOTemplateStyle.text.opacity(0.8))
                                auctionBid(attributes, state: state)
                                    .foregroundColor(CIOTemplateStyle.text)
                            }
                            .font(.subheadline).monospacedDigit()
                        }
                    } else {
                        auctionBid(attributes, state: state)
                            .font(.title.bold()).monospacedDigit()
                            .foregroundColor(CIOTemplateStyle.text)
                        HStack(spacing: 8) {
                            Text(attributes.title)
                            if let subtitle = state.subtitle {
                                Text(subtitle)
                            }
                            HStack(spacing: 2) {
                                Image(systemName: "alarm")
                                Text(timerInterval: Date() ... state.endTime.value, countsDown: true)
                                    .monospacedDigit()
                            }
                        }
                        .font(.caption).foregroundColor(CIOTemplateStyle.text.opacity(0.8)).lineLimit(1)
                    }
                    if let stale = state.staleMessage {
                        Text(stale)
                            .font(.caption2).foregroundColor(CIOTemplateStyle.text.opacity(0.6))
                    }
                }
                Spacer(minLength: 12)
                if let image = attributes.image {
                    CIOAssetImage(key: image).frame(width: 60, height: 60)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
#endif
