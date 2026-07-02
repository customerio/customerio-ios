import Foundation

/// Shared on-disk layout for the Live Activities asset library.
///
/// The main app's `CioLiveActivities` module writes assets and a manifest into the AppGroup
/// container; the widget extension's `CioLiveActivities_Templates` module reads them back.
/// Both sides resolve paths through this single helper so the layout can never drift.
public enum LiveActivityAssetLocation {
    /// Filename of the manifest stored inside the assets directory.
    public static let manifestFilename = "manifest.json"

    /// Resolves the assets directory inside the given AppGroup container root.
    /// Layout: `<container>/cio/assets`.
    public static func assetsDirectory(inContainer containerURL: URL) -> URL {
        containerURL
            .appendingPathComponent("cio")
            .appendingPathComponent("assets")
    }
}
