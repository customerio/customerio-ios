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
                context.attributes.branding.accentColor.flatMap(Color.init(hex:))
                    ?? Color(red: 0.12, green: 0.08, blue: 0.20)
            )
            .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.itemTitle)
                        .font(.caption.bold()).lineLimit(1)
                    Text("\(context.attributes.currencySymbol)\(context.state.currentBid)")
                        .font(.subheadline.bold()).monospacedDigit()
                }
                .padding(.leading, 4)
            }
            DynamicIslandExpandedRegion(.trailing) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Ends in").font(.system(size: 9)).foregroundColor(.secondary)
                    Text(timerInterval: Date() ... context.state.endTime, countsDown: true)
                        .font(.caption.bold()).monospacedDigit()
                }
                .padding(.trailing, 4)
            }
            DynamicIslandExpandedRegion(.bottom) {
                Text(context.state.statusMessage)
                    .font(.caption2)
                    .foregroundColor(context.state.isUserHighBidder ? .green : .secondary)
            }
        } compactLeading: {
            Text("\(context.attributes.currencySymbol)\(context.state.currentBid)")
                .font(.caption.bold()).monospacedDigit()
        } compactTrailing: {
            Text(timerInterval: Date() ... context.state.endTime, countsDown: true)
                .font(.system(size: 10, weight: .bold)).monospacedDigit()
        } minimal: {
            Text(context.attributes.currencySymbol)
                .font(.system(size: 10, weight: .black))
        }
    }
}

// MARK: - Banner

@available(iOS 17.2, *)
private struct AuctionBidBannerView: View {
    let attributes: CIOAuctionBidAttributes
    let state: CIOAuctionBidAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            if let imageKey = attributes.itemImageKey {
                CIOAssetImage(key: imageKey)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    CIOBrandingView(branding: attributes.branding).frame(height: 14)
                    Spacer()
                    Text("\(state.bidCount) bids")
                        .font(.caption2).foregroundColor(.white.opacity(0.6))
                }
                Text(attributes.itemTitle)
                    .font(.caption).foregroundColor(.white.opacity(0.8)).lineLimit(1)
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(attributes.currencySymbol + state.currentBid)
                        .font(.title2.bold()).monospacedDigit().foregroundColor(.white)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Ends in").font(.system(size: 9)).foregroundColor(.white.opacity(0.6))
                        Text(timerInterval: Date() ... state.endTime, countsDown: true)
                            .font(.caption.bold()).monospacedDigit().foregroundColor(.white)
                    }
                }
                Text(state.statusMessage)
                    .font(.caption.bold())
                    .foregroundColor(state.isUserHighBidder ? .green : .white.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
#endif
