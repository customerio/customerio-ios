import Foundation
import Testing

@testable import CioLiveActivities

// MARK: - AssetLibraryWriter.loadData

/// Exercises the data-loading + URL-cache logic of `AssetLibraryWriter` without needing an
/// AppGroup container. The download branch itself requires the network and is validated
/// on-device; here we prove local reads and the cache-hit path (no network) behave correctly.
struct AssetWriterLoadDataTests {
    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cio-asset-writer-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func loadData_readsLocalFileURL_directly() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let fileURL = dir.appendingPathComponent("local.png")
        let bytes = Data("local-bytes".utf8)
        try bytes.write(to: fileURL)

        let loaded = try AssetLibraryWriter.loadData(for: fileURL, cacheDirectory: dir.appendingPathComponent("cache"))
        #expect(loaded == bytes)
    }

    @Test func loadData_returnsCachedBytes_forRemoteURL_withoutNetwork() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Seed the cache exactly where loadData will look, then confirm it is returned
        // for an http(s) URL — proving a cache hit short-circuits the download.
        let remoteURL = URL(string: "https://cdn.example.com/logo.png")!
        let cacheDir = dir.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        let cached = Data("cached-remote-bytes".utf8)
        try cached.write(to: cacheDir.appendingPathComponent(AssetLibraryWriter.cacheFileName(for: remoteURL)))

        let loaded = try AssetLibraryWriter.loadData(for: remoteURL, cacheDirectory: cacheDir)
        #expect(loaded == cached)
    }

    @Test func cacheFileName_isStablePerURL_andDistinctAcrossURLs() {
        let a = URL(string: "https://cdn.example.com/a.png")!
        let b = URL(string: "https://cdn.example.com/b.png")!
        #expect(AssetLibraryWriter.cacheFileName(for: a) == AssetLibraryWriter.cacheFileName(for: a))
        #expect(AssetLibraryWriter.cacheFileName(for: a) != AssetLibraryWriter.cacheFileName(for: b))
    }
}
