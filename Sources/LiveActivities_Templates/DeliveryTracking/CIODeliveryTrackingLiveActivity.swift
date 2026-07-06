#if os(iOS)
@preconcurrency import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Widget

@available(iOS 17.2, *)
public struct CIODeliveryTrackingLiveActivity: Widget {
    public init() {}
    public var body: some WidgetConfiguration { makeDeliveryTrackingConfiguration() }
}

// MARK: - Configuration

// The Live Activity + Dynamic Island DSL (expanded/compact/minimal regions) makes this a single
// long-but-flat declarative body; splitting it would obscure the layout rather than clarify it.
// swiftlint:disable function_body_length
@available(iOS 17.2, *)
@MainActor
private func makeDeliveryTrackingConfiguration()
    -> ActivityConfiguration<CIODeliveryTrackingAttributes> {
    ActivityConfiguration(for: CIODeliveryTrackingAttributes.self) { context in
        DeliveryTrackingBannerView(attributes: context.attributes, state: context.state)
            .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
            .activityBackgroundTint(CIOTemplateStyle.background(fallback: .indigo))
            .activitySystemActionForegroundColor(CIOTemplateStyle.text)
    } dynamicIsland: { context in
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                if let image = context.state.image {
                    CIOAssetImage(key: image)
                        .frame(width: 40, height: 40)
                        .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
                }
            }
            DynamicIslandExpandedRegion(.trailing) {
                if let arrival = context.state.estimatedArrival {
                    if arrival.value > Date() {
                        Text(timerInterval: Date() ... arrival.value, countsDown: true)
                            .font(.caption.bold()).monospacedDigit()
                    } else {
                        // Arrival already passed — a countdown range would be invalid and trap.
                        Text(arrival.value, style: .time)
                            .font(.caption.bold())
                    }
                }
            }
            DynamicIslandExpandedRegion(.bottom) {
                Text(context.state.title)
                    .font(.caption2)
                    .foregroundColor(deliveryStatusColor(context.state.statusColor, fallback: .secondary))
            }
        } compactLeading: {
            if let icon = context.state.progressIcon {
                CIOAssetImage(key: icon)
                    .frame(width: 20, height: 20)
                    .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
            } else {
                DeliveryStepIndicator(
                    current: context.state.progress.current,
                    total: context.state.progress.total
                )
            }
        } compactTrailing: {
            // Static arrival clock time, e.g. "1:45 PM" (not a countdown).
            if let arrival = context.state.estimatedArrival {
                Text(arrival.value, style: .time)
                    .font(.system(size: 13, weight: .semibold))
            }
        } minimal: {
            if let icon = context.state.progressIcon {
                CIOAssetImage(key: icon)
                    .frame(width: 18, height: 18)
                    .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
            } else {
                DeliveryStepIndicator(
                    current: context.state.progress.current,
                    total: context.state.progress.total
                )
            }
        }
    }
}

// swiftlint:enable function_body_length

@available(iOS 17.2, *)
private func deliveryStatusColor(_ hex: String?, fallback: Color) -> Color {
    hex.flatMap(Color.init(hex:)) ?? fallback
}

// MARK: - Banner

@available(iOS 17.2, *)
private struct DeliveryTrackingBannerView: View {
    let attributes: CIODeliveryTrackingAttributes
    let state: CIODeliveryTrackingAttributes.ContentState

    private var statusColor: Color { deliveryStatusColor(state.statusColor, fallback: CIOTemplateStyle.text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    CIOBrandingView(appBranding: CIOLiveActivitiesTemplates.branding, showsName: true)
                        .foregroundColor(CIOTemplateStyle.text)
                    Text(state.title)
                        .font(.title3.bold())
                        .foregroundColor(statusColor)
                    // Static arrival string, e.g. "Arriving at 1:45 PM". The live
                    // countdown lives in the Dynamic Island, where a ticking timer reads well.
                    if let subtitle = state.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundColor(CIOTemplateStyle.text.opacity(0.85))
                    }
                    if let stale = state.staleMessage {
                        Text(stale)
                            .font(.caption2).foregroundColor(CIOTemplateStyle.text.opacity(0.6))
                    }
                }
                Spacer(minLength: 12)
                if let image = state.image {
                    CIOAssetImage(key: image).frame(width: 60, height: 60)
                }
            }
            DeliveryProgressBar(
                current: state.progress.current,
                total: state.progress.total,
                iconKey: state.progressIcon
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Sub-views

/// Full-width segmented progress track with an icon riding the current fill edge.
///
/// The riding icon is `iconKey` resolved via `CIOAssetLibrary`; when absent a plain
/// filled thumb is drawn so the bar degrades gracefully without an asset.
@available(iOS 17.2, *)
private struct DeliveryProgressBar: View {
    let current: Int
    let total: Int
    let iconKey: String?

    private let thumbSize: CGFloat = 28
    private let trackHeight: CGFloat = 4
    private let segmentSpacing: CGFloat = 4

    private var fraction: CGFloat {
        guard total > 0 else { return 0 }
        return min(1, max(0, CGFloat(current) / CGFloat(total)))
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                HStack(spacing: segmentSpacing) {
                    ForEach(1 ... max(1, total), id: \.self) { step in
                        Capsule()
                            .fill(step <= current ? CIOTemplateStyle.text : CIOTemplateStyle.text.opacity(0.3))
                            .frame(height: trackHeight)
                    }
                }
                thumb
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: thumbOffset(width: width))
            }
        }
        .frame(height: thumbSize)
    }

    private func thumbOffset(width: CGFloat) -> CGFloat {
        let center = fraction * width - thumbSize / 2
        return min(max(0, center), max(0, width - thumbSize))
    }

    @ViewBuilder private var thumb: some View {
        if let iconKey {
            CIOAssetImage(key: iconKey)
        } else {
            Circle().fill(CIOTemplateStyle.text)
        }
    }
}

@available(iOS 17.2, *)
private struct DeliveryStepIndicator: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1 ... max(1, total), id: \.self) { step in
                Circle()
                    .fill(step <= current ? Color.white : Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
#endif
