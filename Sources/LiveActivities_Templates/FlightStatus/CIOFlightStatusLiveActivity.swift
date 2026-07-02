#if os(iOS)
@preconcurrency import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Widget

@available(iOS 17.2, *)
public struct CIOFlightStatusLiveActivity: Widget {
    public init() {}
    public var body: some WidgetConfiguration { makeFlightStatusConfiguration() }
}

// MARK: - Configuration

@available(iOS 17.2, *)
@MainActor
private func makeFlightStatusConfiguration()
    -> ActivityConfiguration<CIOFlightStatusAttributes> {
    ActivityConfiguration(for: CIOFlightStatusAttributes.self) { context in
        FlightStatusBannerView(attributes: context.attributes, state: context.state)
            .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
            .activityBackgroundTint(
                CIOLiveActivitiesTemplates.branding?.accentColor.flatMap(Color.init(hex:)) ?? .blue
            )
            .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.origin.code)
                        .font(.caption.bold())
                    Text(context.attributes.origin.city)
                        .font(.system(size: 9)).foregroundColor(.secondary)
                }
                .padding(.leading, 4)
            }
            DynamicIslandExpandedRegion(.trailing) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(context.attributes.destination.code)
                        .font(.caption.bold())
                    Text(context.attributes.destination.city)
                        .font(.system(size: 9)).foregroundColor(.secondary)
                }
                .padding(.trailing, 4)
            }
            DynamicIslandExpandedRegion(.center) {
                FlightProgressBar(fraction: context.state.progressFraction ?? 0)
            }
            DynamicIslandExpandedRegion(.bottom) {
                Text(context.state.title)
                    .font(.caption2)
                    .foregroundColor(flightStatusColor(context.state.statusColor, fallback: .secondary))
            }
        } compactLeading: {
            if let header = context.attributes.header {
                Text(header).font(.caption2.bold())
            } else {
                Image(systemName: "airplane").font(.system(size: 10))
            }
        } compactTrailing: {
            if let status = context.state.status {
                Text(status).font(.system(size: 9)).lineLimit(1)
            }
        } minimal: {
            Image(systemName: "airplane")
                .font(.system(size: 10))
        }
    }
}

@available(iOS 17.2, *)
private func flightStatusColor(_ hex: String?, fallback: Color) -> Color {
    hex.flatMap(Color.init(hex:)) ?? fallback
}

// MARK: - Banner

@available(iOS 17.2, *)
private struct FlightStatusBannerView: View {
    let attributes: CIOFlightStatusAttributes
    let state: CIOFlightStatusAttributes.ContentState

    private var statusColor: Color { flightStatusColor(state.statusColor, fallback: .white) }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                CIOBrandingView(appBranding: CIOLiveActivitiesTemplates.branding).frame(height: 16)
                Spacer()
                if let header = attributes.header {
                    Text(header)
                        .font(.caption.bold()).foregroundColor(.white.opacity(0.8))
                }
            }
            HStack(spacing: 8) {
                FlightEndpointView(
                    code: attributes.origin.code,
                    city: attributes.origin.city,
                    time: state.scheduledDeparture.value
                )
                FlightProgressBar(fraction: state.progressFraction ?? 0)
                FlightEndpointView(
                    code: attributes.destination.code,
                    city: attributes.destination.city,
                    time: state.estimatedArrival.value
                )
            }
            HStack {
                Text(state.title)
                    .font(.caption.bold()).foregroundColor(statusColor)
                Spacer()
                if let status = state.status {
                    Text(status)
                        .font(.caption.bold()).foregroundColor(.white.opacity(0.8))
                }
            }
            if let subtitle = state.subtitle {
                Text(subtitle)
                    .font(.caption2).foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let stale = state.staleMessage {
                Text(stale)
                    .font(.caption2).foregroundColor(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Sub-views

@available(iOS 17.2, *)
private struct FlightEndpointView: View {
    let code: String
    let city: String
    let time: Date

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        VStack(spacing: 2) {
            Text(code).font(.headline).foregroundColor(.white)
            Text(city).font(.system(size: 9)).foregroundColor(.white.opacity(0.7)).lineLimit(1)
            Text(Self.timeFormatter.string(from: time))
                .font(.caption2.bold()).foregroundColor(.white.opacity(0.8))
        }
        .frame(minWidth: 52)
    }
}

@available(iOS 17.2, *)
private struct FlightProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 3)
                Capsule()
                    .fill(Color.white)
                    .frame(width: geo.size.width * max(0, min(1, fraction)), height: 3)
                Image(systemName: "airplane")
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .offset(x: geo.size.width * max(0, min(1, fraction)) - 6, y: -6)
            }
        }
        .frame(height: 20)
    }
}
#endif
