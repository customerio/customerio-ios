#if os(iOS)
import ActivityKit
import CioLiveActivities_Attributes
import SwiftUI
import WidgetKit

/// The Customer.io **Segments** Live Activity widget.
///
/// Add this to your widget extension's `WidgetBundle`, passing your app's ``CIOSegmentsBranding``.
/// It renders ``CIOSegmentsAttributes`` on the Lock Screen and in the Dynamic Island, and wires the
/// tap deep link from the Customer.io push metadata:
///
/// ```swift
/// @main
/// struct MyWidgets: WidgetBundle {
///     var body: some Widget {
///         CIOSegmentsLiveActivity(branding: CIOSegmentsBranding(logo: Image("brand-logo")))
///     }
/// }
/// ```
@available(iOS 16.2, *)
public struct CIOSegmentsLiveActivity: Widget {
    private let branding: CIOSegmentsBranding

    /// `Widget` requires a no-argument initializer so WidgetKit can construct the type; this uses
    /// the default (dark) branding. Prefer ``init(branding:)`` from your `WidgetBundle` to style it.
    public init() {
        self.branding = CIOSegmentsBranding()
    }

    public init(branding: CIOSegmentsBranding) {
        self.branding = branding
    }

    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: CIOSegmentsAttributes.self) { context in
            SegmentsLockScreenView(attributes: context.attributes, state: context.state, branding: branding)
                .modifier(TemplateBackgroundModifier(background: branding.background))
                .cioWidgetUrl(context.state.cioMetadata)
        } dynamicIsland: { context in
            dynamicIsland(for: context)
        }
    }

    @available(iOS 16.2, *)
    private func dynamicIsland(for context: ActivityViewContext<CIOSegmentsAttributes>) -> DynamicIsland {
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                BrandLogo(logo: branding.logo, size: 24)
            }
            DynamicIslandExpandedRegion(.trailing) {
                if let trailing = context.state.trailingText {
                    Text(trailing).font(.caption).foregroundStyle(.secondary)
                }
            }
            DynamicIslandExpandedRegion(.bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(context.state.status).font(.headline)
                    SegmentedBar(state: context.state, branding: branding)
                }
            }
        } compactLeading: {
            BrandLogo(logo: branding.logo, size: 20)
        } compactTrailing: {
            if let trailing = context.state.trailingText {
                Text(trailing).font(.caption2)
            }
        } minimal: {
            BrandLogo(logo: branding.logo, size: 20)
        }
        .cioWidgetUrl(context.state.cioMetadata)
    }
}

// MARK: - Lock Screen

@available(iOS 16.2, *)
private struct SegmentsLockScreenView: View {
    let attributes: CIOSegmentsAttributes
    let state: CIOSegmentsAttributes.ContentState
    let branding: CIOSegmentsBranding

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                BrandLogo(logo: branding.logo, size: 22)
                Text(attributes.header).font(.subheadline)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(state.status).font(.title3.bold())
                if let substatus = state.substatus {
                    Text(substatus).font(.subheadline).opacity(0.8)
                }
            }

            SegmentedBar(state: state, branding: branding)
        }
        .foregroundStyle(branding.textColor)
        .padding()
        // Read the whole card as one coherent VoiceOver element (header, status, substatus, and the
        // bar's "step X of Y" label) instead of announcing each piece separately.
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Segmented progress bar

@available(iOS 16.2, *)
private struct SegmentedBar: View {
    let state: CIOSegmentsAttributes.ContentState
    let branding: CIOSegmentsBranding

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0 ..< state.clampedTotal, id: \.self) { index in
                Capsule()
                    .fill(index < state.clampedComplete ? branding.progressCompleteStyle : branding.progressIncompleteStyle)
                    .frame(height: 4)
            }
        }
        .accessibilityLabel("Step \(state.clampedComplete) of \(state.clampedTotal)")
    }
}
#endif
