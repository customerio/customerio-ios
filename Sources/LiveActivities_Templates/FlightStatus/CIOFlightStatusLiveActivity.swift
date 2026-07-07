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
            .activityBackgroundTint(CIOTemplateStyle.background(fallback: .blue))
            .activitySystemActionForegroundColor(CIOTemplateStyle.text)
            .widgetURL(context.state.cioMetadata?.deepLink.flatMap(URL.init(string:)))
    } dynamicIsland: { context in
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.origin.code).font(.caption.bold())
                    Text(context.attributes.origin.city)
                        .font(.system(size: 9)).foregroundColor(.secondary)
                }
                .padding(.leading, 4)
            }
            DynamicIslandExpandedRegion(.trailing) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(context.attributes.destination.code).font(.caption.bold())
                    Text(context.attributes.destination.city)
                        .font(.system(size: 9)).foregroundColor(.secondary)
                }
                .padding(.trailing, 4)
            }
            DynamicIslandExpandedRegion(.center) {
                // Island renders on the black pill — keep the bar light.
                FlightProgressBar(fraction: context.state.progressFraction ?? 0, color: .white)
            }
            DynamicIslandExpandedRegion(.bottom) {
                Text(context.state.title)
                    .font(.caption2)
                    .foregroundColor(flightStatusColor(context.state.statusColor, fallback: .secondary))
            }
        } compactLeading: {
            CIOBrandingView(appBranding: CIOLiveActivitiesTemplates.branding)
                .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
                .frame(width: 20, height: 20)
        } compactTrailing: {
            flightCompactTime(context.state)
        } minimal: {
            CIOBrandingView(appBranding: CIOLiveActivitiesTemplates.branding)
                .environment(\.cioAssetLibrary, CIOLiveActivitiesTemplates.assetLibrary)
                .frame(width: 18, height: 18)
        }
    }
}

@available(iOS 17.2, *)
private func flightStatusColor(_ hex: String?, fallback: Color) -> Color {
    hex.flatMap(Color.init(hex:)) ?? fallback
}

/// Compact trailing time: a countdown to the next event (departure, then arrival), or the
/// clock time once it has passed. The range is only built before the target, so it can't trap.
@available(iOS 17.2, *)
@ViewBuilder
private func flightCompactTime(_ state: CIOFlightStatusAttributes.ContentState) -> some View {
    let now = Date()
    let target = now < state.scheduledDeparture.value ? state.scheduledDeparture.value : state.estimatedArrival.value
    if now < target {
        Text(timerInterval: now ... target, countsDown: true)
            .font(.system(size: 11, weight: .bold)).monospacedDigit()
    } else {
        Text(target, style: .time)
            .font(.system(size: 11, weight: .bold))
    }
}

// MARK: - Banner

@available(iOS 17.2, *)
private struct FlightStatusBannerView: View {
    let attributes: CIOFlightStatusAttributes
    let state: CIOFlightStatusAttributes.ContentState

    private var isLanded: Bool { Date() >= state.estimatedArrival.value }
    private var isInFlight: Bool { state.progressFraction != nil && !isLanded }
    private var statusColor: Color { flightStatusColor(state.statusColor, fallback: CIOTemplateStyle.text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Top: brand logo + flight number, status on the right (hidden once landed).
            HStack(spacing: 6) {
                CIOBrandingView(appBranding: CIOLiveActivitiesTemplates.branding)
                    .frame(width: 22, height: 22)
                if let header = attributes.header {
                    Text(header).font(.subheadline.weight(.semibold))
                }
                Spacer()
                if !isLanded, let status = state.status {
                    Text(status).font(.subheadline).foregroundColor(statusColor)
                }
            }
            .foregroundColor(CIOTemplateStyle.text)

            Text(state.title)
                .font(.title3.bold())
                .foregroundColor(CIOTemplateStyle.text)
                .frame(maxWidth: .infinity, alignment: isInFlight ? .center : .leading)

            // In-flight shows the progress bar; otherwise the freeform detail line.
            if isInFlight {
                FlightProgressBar(fraction: state.progressFraction ?? 0, color: CIOTemplateStyle.text)
            } else if let subtitle = state.subtitle {
                Text(subtitle)
                    .font(.subheadline).foregroundColor(CIOTemplateStyle.text.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Route row, hidden once landed.
            if !isLanded {
                FlightRouteRow(origin: attributes.origin, destination: attributes.destination, color: CIOTemplateStyle.text)
            }

            if let stale = state.staleMessage {
                Text(stale)
                    .font(.caption2).foregroundColor(CIOTemplateStyle.text.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Sub-views

@available(iOS 17.2, *)
private struct FlightRouteRow: View {
    let origin: CIOFlightStatusAttributes.Airport
    let destination: CIOFlightStatusAttributes.Airport
    let color: Color

    var body: some View {
        HStack {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(origin.code).font(.title3.bold())
                Text("Departure").font(.caption).foregroundColor(color.opacity(0.7))
            }
            Spacer()
            Image(systemName: "airplane")
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Arrival").font(.caption).foregroundColor(color.opacity(0.7))
                Text(destination.code).font(.title3.bold())
            }
        }
        .foregroundColor(color)
    }
}

@available(iOS 17.2, *)
private struct FlightProgressBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.3)).frame(height: 4)
                Capsule().fill(color)
                    .frame(width: geo.size.width * max(0, min(1, fraction)), height: 4)
            }
        }
        .frame(height: 4)
    }
}
#endif
