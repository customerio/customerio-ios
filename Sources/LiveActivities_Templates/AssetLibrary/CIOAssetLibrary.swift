import Foundation
import SwiftUI

/// Provides read access to image assets pre-loaded into the AppGroup container
/// by the main app's `CIOLiveActivities` module.
///
/// Obtain the shared instance via `CIOLiveActivitiesTemplates.assetLibrary`, which is
/// configured once in `WidgetBundle.init()` via `CIOLiveActivitiesTemplates.configure(appGroup:)`.
///
/// Third-party Live Activity widgets that are not built on Customer.io templates
/// can access the same instance directly:
/// ```swift
/// let assetLibrary = CIOLiveActivitiesTemplates.assetLibrary
/// ```
public final class CIOAssetLibrary: Sendable {
    // The path of the assets directory relative to the AppGroup container root.
    //
    // NOTE: This value must match `AssetLibraryWriter.assetsSubpath` in
    // Sources/LiveActivities/AssetLibrary/AssetLibraryWriter.swift.
    // Both sides must always agree on this path.
    private static let assetsSubpath = "cio/assets"
    private static let manifestFilename = "manifest.json"

    /// The resolved assets directory URL. `nil` on a null instance.
    private let assetsURL: URL?

    /// In-memory snapshot of the manifest, loaded once at init time.
    private let assets: [String: ManifestEntry]

    // MARK: - Initializers

    /// Create a null instance.
    ///
    /// Every asset lookup returns `nil` / renders an empty placeholder. Use this
    /// as a safe default when no AppGroup has been configured.
    public init(path: URL?) {
        self.assetsURL = path
        self.assets = path.flatMap { Self.loadManifest(assetsURL: $0) } ?? [:]
    }

    /// Create an instance backed by an AppGroup container.
    ///
    /// Locates the AppGroup container and validates that the assets directory and
    /// manifest file exist. Throws if either is absent — call `init(path:)` with
    /// `nil` if you need a safe fallback instead.
    ///
    /// - Parameter appGroup: The AppGroup container identifier (e.g. `"group.com.example.app"`).
    /// - Throws: `CIOAssetLibraryError` if the container or manifest cannot be found.
    public convenience init(appGroup: String) throws {
        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroup
            )
        else {
            throw CIOAssetLibraryError.appGroupNotFound(appGroup)
        }
        let assetsURL = containerURL
            .appendingPathComponent("cio")
            .appendingPathComponent("assets")
        let manifestURL = assetsURL.appendingPathComponent(Self.manifestFilename)
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw CIOAssetLibraryError.manifestNotFound(appGroup)
        }
        self.init(path: assetsURL)
    }

    // MARK: - Resolution

    /// Returns the file URL of the asset stored under `key`, or `nil` if the key
    /// is not present in the manifest or the library is a null instance.
    public func url(for key: String) -> URL? {
        guard let assetsURL, let entry = assets[key] else { return nil }
        return assetsURL.appendingPathComponent("\(entry.hash).\(entry.ext)")
    }

    /// Returns a SwiftUI view that displays the asset stored under `key`.
    ///
    /// Renders an empty placeholder when the key is absent or the library is a
    /// null instance. The concrete placeholder type is an implementation detail
    /// and should not be relied upon.
    @ViewBuilder
    public func image(for key: String) -> some View {
        #if os(iOS)
        if let url = url(for: key),
           let uiImage = UIImage(contentsOfFile: url.path) {
            Image(uiImage: uiImage)
        } else {
            Color.clear
        }
        #else
        Color.clear
        #endif
    }

    // MARK: - Private

    private struct ManifestEntry: Decodable {
        let hash: String
        let ext: String
    }

    private struct Manifest: Decodable {
        let version: Int
        let assets: [String: ManifestEntry]
    }

    private static func loadManifest(assetsURL: URL) -> [String: ManifestEntry]? {
        let manifestURL = assetsURL.appendingPathComponent(manifestFilename)
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return (try? JSONDecoder().decode(Manifest.self, from: data))?.assets
    }
}

// MARK: -

public enum CIOAssetLibraryError: Error {
    /// The AppGroup container could not be resolved for the given identifier.
    case appGroupNotFound(String)
    /// The AppGroup container exists but no asset manifest was found within it.
    case manifestNotFound(String)
}
