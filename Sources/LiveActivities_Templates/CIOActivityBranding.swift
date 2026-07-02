#if os(iOS)

/// App-level branding shared across all Customer.io Live Activity templates.
///
/// Registered once in the widget extension via
/// `CIOLiveActivitiesTemplates.configure(appGroup:branding:)` and applied to every
/// template this app renders — it is *not* set per activity type. Mirrors the Android
/// `LiveNotificationBranding` app-level configuration.
public struct CIOActivityBranding: Codable, Hashable, Sendable {
    /// AssetKey for the brand logo image, resolved via `CIOAssetLibrary`.
    /// When `nil` or the key is not found, `name` is displayed as a text fallback.
    public var logoKey: String?

    /// Human-readable brand name. Always displayed when no logo is available.
    public var name: String

    /// Hex color string for the brand accent color (e.g. `"#FF5733"`).
    /// `nil` uses the template's built-in default.
    public var accentColor: String?

    public init(name: String, logoKey: String? = nil, accentColor: String? = nil) {
        self.name = name
        self.logoKey = logoKey
        self.accentColor = accentColor
    }
}

#endif
