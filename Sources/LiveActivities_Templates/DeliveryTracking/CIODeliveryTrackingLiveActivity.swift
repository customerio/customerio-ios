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

@available(iOS 17.2, *)
@MainActor
private func makeDeliveryTrackingConfiguration()
    -> ActivityConfiguration<CIODeliveryTrackingAttributes> {
    ActivityConfiguration(for: CIODeliveryTrackingAttributes.self) { context in
        DeliveryTrackingBannerView(attributes: context.attributes, state: context.state)
            .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
            .activityBackgroundTint(
                CIOLiveActivitiesTemplates.branding?.accentColor.flatMap(Color.init(hex:)) ?? .indigo
            )
            .activitySystemActionForegroundColor(.white)
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
                    Text(timerInterval: Date() ... arrival.value, countsDown: true)
                        .font(.caption.bold()).monospacedDigit()
                }
            }
            DynamicIslandExpandedRegion(.bottom) {
                Text(context.state.title)
                    .font(.caption2)
                    .foregroundColor(deliveryStatusColor(context.state.statusColor, fallback: .secondary))
            }
        } compactLeading: {
            DeliveryStepIndicator(
                current: context.state.progress.current,
                total: context.state.progress.total
            )
        } compactTrailing: {
            if let arrival = context.state.estimatedArrival {
                Text(timerInterval: Date() ... arrival.value, countsDown: true)
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
            }
        } minimal: {
            DeliveryStepIndicator(
                current: context.state.progress.current,
                total: context.state.progress.total
            )
        }
    }
}

@available(iOS 17.2, *)
private func deliveryStatusColor(_ hex: String?, fallback: Color) -> Color {
    hex.flatMap(Color.init(hex:)) ?? fallback
}

// MARK: - Banner

@available(iOS 17.2, *)
private struct DeliveryTrackingBannerView: View {
    let attributes: CIODeliveryTrackingAttributes
    let state: CIODeliveryTrackingAttributes.ContentState

    private var statusColor: Color { deliveryStatusColor(state.statusColor, fallback: .white) }

    var body: some View {
        HStack(spacing: 12) {
            if let image = state.image {
                CIOAssetImage(key: image).frame(width: 48, height: 48)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if let header = attributes.header {
                        Text(header)
                            .font(.caption2).foregroundColor(.white.opacity(0.7))
                    } else {
                        CIOBrandingView(appBranding: CIOLiveActivitiesTemplates.branding).frame(height: 16)
                    }
                    Spacer()
                    DeliveryStepIndicator(
                        current: state.progress.current,
                        total: state.progress.total
                    )
                }
                Text(state.title)
                    .font(.subheadline.bold())
                    .foregroundColor(statusColor)
                if let arrival = state.estimatedArrival {
                    Text(timerInterval: Date() ... arrival.value, countsDown: true)
                        .font(.caption.bold()).monospacedDigit()
                        .foregroundColor(.white)
                }
                if let subtitle = state.subtitle {
                    Text(subtitle)
                        .font(.caption2).foregroundColor(.white.opacity(0.7))
                }
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
