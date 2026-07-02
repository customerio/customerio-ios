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
            .activityBackgroundTint(
                CIOLiveActivitiesTemplates.branding?.accentColor.flatMap(Color.init(hex:))
                    ?? Color(red: 0.12, green: 0.08, blue: 0.20)
            )
            .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.title)
                        .font(.caption.bold()).lineLimit(1)
                    HStack(spacing: 0) {
                        Text(context.attributes.currencySymbol)
                        Text(context.state.currentBid)
                    }
                    .font(.subheadline.bold()).monospacedDigit()
                }
                .padding(.leading, 4)
            }
            DynamicIslandExpandedRegion(.trailing) {
                Text(timerInterval: Date() ... context.state.endTime.value, countsDown: true)
                    .font(.caption.bold()).monospacedDigit()
                    .padding(.trailing, 4)
            }
            DynamicIslandExpandedRegion(.bottom) {
                Text(context.state.statusMessage)
                    .font(.caption2)
                    .foregroundColor(auctionStatusColor(context.state.statusColor, fallback: .secondary))
            }
        } compactLeading: {
            HStack(spacing: 0) {
                Text(context.attributes.currencySymbol)
                Text(context.state.currentBid)
            }
            .font(.caption.bold()).monospacedDigit()
        } compactTrailing: {
            Text(timerInterval: Date() ... context.state.endTime.value, countsDown: true)
                .font(.system(size: 10, weight: .bold)).monospacedDigit()
        } minimal: {
            Text(context.attributes.currencySymbol)
                .font(.system(size: 10, weight: .black))
        }
    }
}

@available(iOS 17.2, *)
private func auctionStatusColor(_ hex: String?, fallback: Color) -> Color {
    hex.flatMap(Color.init(hex:)) ?? fallback
}

// MARK: - Banner

@available(iOS 17.2, *)
private struct AuctionBidBannerView: View {
    let attributes: CIOAuctionBidAttributes
    let state: CIOAuctionBidAttributes.ContentState

    private var statusColor: Color { auctionStatusColor(state.statusColor, fallback: .white.opacity(0.7)) }

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
                            .font(.caption2).foregroundColor(.white.opacity(0.6))
                    } else {
                        CIOBrandingView(appBranding: CIOLiveActivitiesTemplates.branding).frame(height: 14)
                    }
                    Spacer()
                    if let subtitle = state.subtitle {
                        Text(subtitle)
                            .font(.caption2).foregroundColor(.white.opacity(0.6))
                    }
                }
                Text(attributes.title)
                    .font(.caption).foregroundColor(.white.opacity(0.8)).lineLimit(1)
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    HStack(spacing: 0) {
                        Text(attributes.currencySymbol)
                        Text(state.currentBid)
                    }
                    .font(.title2.bold()).monospacedDigit().foregroundColor(.white)
                    Spacer()
                    Text(timerInterval: Date() ... state.endTime.value, countsDown: true)
                        .font(.caption.bold()).monospacedDigit().foregroundColor(.white)
                }
                Text(state.statusMessage)
                    .font(.caption.bold())
                    .foregroundColor(statusColor)
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
#endif
