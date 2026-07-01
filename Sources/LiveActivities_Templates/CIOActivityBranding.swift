#if os(iOS)

/// Branding configuration shared across all Customer.io Live Activity templates.
///
/// Embed this in the static `ActivityAttributes` of any template to allow the
/// host app to supply a logo asset and accent color at activity-creation time.
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
