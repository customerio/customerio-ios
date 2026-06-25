import CryptoKit
import Foundation

/// Syncs declared bundle assets into the AppGroup container and maintains the
/// asset manifest read by `CIOAssetLibrary` in the widget extension.
///
/// Sync is idempotent — assets whose SHA-256 hash is unchanged are skipped.
/// A garbage-collection sweep removes unreferenced hash files after each write.
struct AssetLibraryWriter {

    // The path of the assets directory relative to the AppGroup container root.
    //
    // NOTE: This value must match `CIOAssetLibrary.assetsSubpath` in
    // Sources/LiveActivities_Templates/AssetLibrary/CIOAssetLibrary.swift.
    // Both sides must always agree on this path.
    private static let assetsSubpath = "cio/assets"
    private static let manifestFilename = "manifest.json"

    private let assetsURL: URL

    /// - Throws: `AssetLibraryError.appGroupNotFound` if the AppGroup container
    ///   cannot be resolved for the given identifier.
    init(appGroupIdentifier: String) throws {
        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else {
            throw AssetLibraryError.appGroupNotFound(appGroupIdentifier)
        }
        self.assetsURL = containerURL
            .appendingPathComponent("cio")
            .appendingPathComponent("assets")
    }

    /// Copy new or changed assets into the AppGroup, update the manifest, and
    /// sweep unreferenced files.
    ///
    /// - Parameter registrations: The declared assets from `LiveActivityConfig`.
    /// - Throws: File-system or encoding errors.
    func sync(registrations: [AssetRegistration]) throws {
        try FileManager.default.createDirectory(
            at: assetsURL, withIntermediateDirectories: true)

        var manifest = loadManifest() ?? AssetManifest()

        for registration in registrations {
            let data = try Data(contentsOf: registration.sourceURL)
            let hash = sha256(of: data)
            let ext = registration.sourceURL.pathExtension

            // Skip if the stored hash already matches.
            if let existing = manifest.assets[registration.key], existing.hash == hash {
                continue
            }

            let destURL = assetsURL.appendingPathComponent("\(hash).\(ext)")
            try data.write(to: destURL, options: .atomic)
            manifest.assets[registration.key] = AssetManifest.Entry(hash: hash, ext: ext)
        }

        let manifestURL = assetsURL.appendingPathComponent(Self.manifestFilename)
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: manifestURL, options: .atomic)

        try sweep(manifest: manifest)
    }

    // MARK: - Private

    private func loadManifest() -> AssetManifest? {
        let manifestURL = assetsURL.appendingPathComponent(Self.manifestFilename)
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? JSONDecoder().decode(AssetManifest.self, from: data)
    }

    /// Delete any file in the assets directory that is not referenced by the
    /// current manifest. The manifest file itself is always retained.
    private func sweep(manifest: AssetManifest) throws {
        let referenced = Set(manifest.assets.values.map { "\($0.hash).\($0.ext)" })
        let contents = try FileManager.default.contentsOfDirectory(atPath: assetsURL.path)
        for filename in contents where filename != Self.manifestFilename {
            if !referenced.contains(filename) {
                try? FileManager.default.removeItem(
                    at: assetsURL.appendingPathComponent(filename))
            }
        }
    }

    private func sha256(of data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

// MARK: -

enum AssetLibraryError: Error {
    case appGroupNotFound(String)
}
