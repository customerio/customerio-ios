#if os(iOS)

/// App-level branding shared across all Customer.io Live Activity templates.
///
/// Registered once in the widget extension via
/// `CIOLiveActivitiesTemplates.configure(appGroup:branding:)` and applied to every
/// template this app renders — it is *not* set per activity type. Mirrors the Android
/// `LiveNotificationBranding` app-level configuration.
public struct CIOActivityBranding: Codable, Hashable, Sendable {
    /// AssetKey for the brand logo image, resolved via `CIOAssetLibrary`.
    /// When `nil` or the key is not found, no brand mark is rendered.
    public var logoKey: String?

    /// Hex color string (e.g. `"#FF5733"`) for the lock-screen card background.
    /// `nil` uses each template's built-in default.
    public var backgroundColor: String?

    /// Hex color for lock-screen text/scores. `nil` defaults to white.
    public var textColor: String?

    public init(
        logoKey: String? = nil,
        backgroundColor: String? = nil,
        textColor: String? = nil
    ) {
        self.logoKey = logoKey
        self.backgroundColor = backgroundColor
        self.textColor = textColor
    }
}

#endif
