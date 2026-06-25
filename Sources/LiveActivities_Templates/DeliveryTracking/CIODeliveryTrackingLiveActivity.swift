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
    -> ActivityConfiguration<CIODeliveryTrackingAttributes>
{
    ActivityConfiguration(for: CIODeliveryTrackingAttributes.self) { context in
        DeliveryTrackingBannerView(attributes: context.attributes, state: context.state)
            .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
            .activityBackgroundTint(
                context.attributes.branding.accentColor.flatMap(Color.init(hex:)) ?? .indigo)
            .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                if let key = context.state.statusImageKey {
                    CIOAssetImage(key: key)
                        .frame(width: 40, height: 40)
                        .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
                }
            }
            DynamicIslandExpandedRegion(.trailing) {
                if let arrival = context.state.estimatedArrival {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("ETA").font(.system(size: 9)).foregroundColor(.secondary)
                        Text(timerInterval: Date()...arrival, countsDown: true)
                            .font(.caption.bold()).monospacedDigit()
                    }
                }
            }
            DynamicIslandExpandedRegion(.bottom) {
                Text(context.state.statusMessage)
                    .font(.caption2).foregroundColor(.secondary)
            }
        } compactLeading: {
            DeliveryStepIndicator(
                current: context.state.stepCurrent,
                total: context.state.stepTotal
            )
        } compactTrailing: {
            if let arrival = context.state.estimatedArrival {
                Text(timerInterval: Date()...arrival, countsDown: true)
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
            }
        } minimal: {
            DeliveryStepIndicator(
                current: context.state.stepCurrent,
                total: context.state.stepTotal
            )
        }
    }
}

// MARK: - Banner

@available(iOS 17.2, *)
private struct DeliveryTrackingBannerView: View {
    let attributes: CIODeliveryTrackingAttributes
    let state: CIODeliveryTrackingAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            if let key = state.statusImageKey {
                CIOAssetImage(key: key).frame(width: 48, height: 48)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    CIOBrandingView(branding: attributes.branding).frame(height: 16)
                    Spacer()
                    DeliveryStepIndicator(
                        current: state.stepCurrent,
                        total: state.stepTotal
                    )
                }
                Text(state.statusMessage)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                if let arrival = state.estimatedArrival {
                    HStack(spacing: 4) {
                        Text("ETA")
                            .font(.caption).foregroundColor(.white.opacity(0.7))
                        Text(timerInterval: Date()...arrival, countsDown: true)
                            .font(.caption.bold()).monospacedDigit()
                            .foregroundColor(.white)
                    }
                }
                if let driver = state.driverName {
                    Text("Driver: \(driver)")
                        .font(.caption2).foregroundColor(.white.opacity(0.7))
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
            ForEach(1...max(1, total), id: \.self) { step in
                Circle()
                    .fill(step <= current ? Color.white : Color.white.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
#endif
