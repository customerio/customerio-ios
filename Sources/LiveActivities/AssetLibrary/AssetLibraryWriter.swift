import CioLiveActivities_Attributes
import CryptoKit
import Foundation

/// Syncs declared bundle assets into the AppGroup container and maintains the
/// asset manifest read by `CIOAssetLibrary` in the widget extension.
///
/// Sync is idempotent — assets whose SHA-256 hash is unchanged are skipped.
/// A garbage-collection sweep removes unreferenced hash files after each write.
///
/// Remote (`http`/`https`) assets are downloaded and cached on disk keyed by the URL
/// hash, so a later sync of the same URL reads the cached bytes instead of re-fetching
/// (mirrors the Android `TemplateAssets` URL cache). Sync always runs off the init thread
/// (see `LiveActivitiesModule.syncAssets`), so the download never blocks initialization.
/// The URL cache has no expiry — a URL is assumed immutable; publish changed art under a
/// new URL (or asset key).
struct AssetLibraryWriter {
    /// Subdirectory (under the assets directory) holding downloaded remote assets, keyed by
    /// URL hash. Never read by the widget — it only consults content-addressed hash files.
    static let cacheDirName = "cache"

    private let assetsURL: URL
    private var cacheURL: URL { assetsURL.appendingPathComponent(Self.cacheDirName) }

    /// - Throws: `AssetLibraryError.appGroupNotFound` if the AppGroup container
    ///   cannot be resolved for the given identifier.
    init(appGroupIdentifier: String) throws {
        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
            )
        else {
            throw AssetLibraryError.appGroupNotFound(appGroupIdentifier)
        }
        self.assetsURL = LiveActivityAssetLocation.assetsDirectory(inContainer: containerURL)
    }

    /// Copy new or changed assets into the AppGroup, update the manifest, and
    /// sweep unreferenced files.
    ///
    /// - Parameter registrations: The declared assets from `LiveActivityConfig`.
    /// - Throws: File-system, network, or encoding errors.
    func sync(registrations: [AssetRegistration]) throws {
        try FileManager.default.createDirectory(
            at: assetsURL, withIntermediateDirectories: true
        )

        var manifest = loadManifest() ?? AssetManifest()

        for registration in registrations {
            let data = try Self.loadData(for: registration.sourceURL, cacheDirectory: cacheURL)
            let hash = Self.sha256(of: data)
            let ext = registration.sourceURL.pathExtension

            // Skip if the stored hash already matches.
            if let existing = manifest.assets[registration.key], existing.hash == hash {
                continue
            }

            let destURL = assetsURL.appendingPathComponent("\(hash).\(ext)")
            try data.write(to: destURL, options: .atomic)
            manifest.assets[registration.key] = AssetManifest.Entry(hash: hash, ext: ext)
        }

        let manifestURL = assetsURL.appendingPathComponent(LiveActivityAssetLocation.manifestFilename)
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: manifestURL, options: .atomic)

        try sweep(manifest: manifest)
    }

    // MARK: - Data loading

    /// Loads the bytes for `sourceURL`.
    ///
    /// Local URLs are read directly. Remote (`http`/`https`) URLs are downloaded once and
    /// cached under `cacheDirectory` keyed by the URL hash; a later call for the same URL
    /// returns the cached bytes without hitting the network.
    static func loadData(for sourceURL: URL, cacheDirectory: URL) throws -> Data {
        guard let scheme = sourceURL.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return try Data(contentsOf: sourceURL)
        }
        let cacheFile = cacheDirectory.appendingPathComponent(cacheFileName(for: sourceURL))
        if let cached = try? Data(contentsOf: cacheFile) {
            return cached
        }
        let downloaded = try Data(contentsOf: sourceURL)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? downloaded.write(to: cacheFile, options: .atomic)
        return downloaded
    }

    /// The on-disk cache filename (URL hash) for a remote asset URL.
    static func cacheFileName(for sourceURL: URL) -> String {
        sha256(of: Data(sourceURL.absoluteString.utf8))
    }

    // MARK: - Private

    private func loadManifest() -> AssetManifest? {
        let manifestURL = assetsURL.appendingPathComponent(LiveActivityAssetLocation.manifestFilename)
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? JSONDecoder().decode(AssetManifest.self, from: data)
    }

    /// Delete any file in the assets directory that is not referenced by the
    /// current manifest. The manifest file and the URL cache directory are always retained.
    private func sweep(manifest: AssetManifest) throws {
        let referenced = Set(manifest.assets.values.map { "\($0.hash).\($0.ext)" })
        let contents = try FileManager.default.contentsOfDirectory(atPath: assetsURL.path)
        for filename in contents
            where filename != LiveActivityAssetLocation.manifestFilename && filename != Self.cacheDirName {
            if !referenced.contains(filename) {
                try? FileManager.default.removeItem(
                    at: assetsURL.appendingPathComponent(filename)
                )
            }
        }
    }

    static func sha256(of data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

// MARK: -

enum AssetLibraryError: Error {
    case appGroupNotFound(String)
}
