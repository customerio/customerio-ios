import Foundation

/// On-disk representation of the asset library manifest.
///
/// Written by `AssetLibraryWriter` and read by `CIOAssetLibrary` in the widget
/// extension. Both sides must agree on this schema — any change here must be
/// reflected in `Sources/LiveActivities_Templates/AssetLibrary/CIOAssetLibrary.swift`.
struct AssetManifest: Codable {
    let version: Int

    /// AssetKey → entry mapping.
    var assets: [String: Entry]

    struct Entry: Codable {
        /// Lowercase hex SHA-256 of the file contents.
        let hash: String
        /// File extension without the leading dot (e.g. `"png"`, `"jpg"`).
        let ext: String
    }

    init(version: Int = 1, assets: [String: Entry] = [:]) {
        self.version = version
        self.assets = assets
    }
}
