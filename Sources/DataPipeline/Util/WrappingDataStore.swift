//
//  WrappingDataStore.swift
//
//  SPIKE-ONLY — feasibility test for Phase 3 encryption-at-rest.
//  Wraps cdp-analytics-swift's storage so we can prove that every byte
//  the event-queue path persists flows through our custom DataStore.
//
//  Mutation:
//    - Prepend the sentinel  "WRAPPED::v1::"  (13 ASCII bytes)
//    - XOR every byte AFTER the sentinel with 0x55
//
//  On fetch we reverse the mutation and hand the library a fully-formed
//  JSON batch (matching the MemoryStore contract) so the upload pipeline
//  never sees the wrapped form.
//
//  This is throwaway code on a spike branch. Do not ship.
//

import CioAnalytics
import Foundation
import os.log

// MARK: - Trace logger

private let spikeLog = OSLog(subsystem: "io.customer.spike", category: "SegmentStorageTrace")

@inline(__always)
private func tracePreview(_ bytes: Data, max: Int = 64) -> String {
    let slice = bytes.prefix(max)
    // Hex preview — readable in `log stream` without binary noise.
    return slice.map { String(format: "%02x", $0) }.joined()
}

// MARK: - WrappingDataStore

/// A `DataStore` implementation that
/// (a) traces every protocol-method call via `os_log`, and
/// (b) writes events to disk in a *mutated* form so a grep for the
///     pre-mutation plaintext on disk proves whether the library
///     bypasses this store on any persistence path.
public final class WrappingDataStore: DataStore {
    public typealias StoreConfiguration = Configuration

    public struct Configuration {
        let writeKey: String
        let storageLocation: URL
        let maxFetchSize: Int

        public init(writeKey: String, storageLocation: URL, maxFetchSize: Int) {
            self.writeKey = writeKey
            self.storageLocation = storageLocation
            self.maxFetchSize = maxFetchSize
        }
    }

    // Sentinel + XOR key used to mutate every persisted byte.
    public static let sentinel: Data = Data("WRAPPED::v1::".utf8)
    public static let xorKey: UInt8 = 0x55

    private let config: Configuration
    // Each persisted file holds exactly one wrapped event so we don't have
    // to deal with separators or in-place mutation of multi-event files.
    private let lock = NSLock()
    // Monotonically increasing index — used only for filename ordering.
    private var nextIndex: Int = 0

    public var transactionType: DataTransactionType { .data }

    public var hasData: Bool { count > 0 }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return (try? FileManager.default.contentsOfDirectory(at: config.storageLocation, includingPropertiesForKeys: nil))?.count ?? 0
    }

    public required init(configuration: Configuration) {
        self.config = configuration
        try? FileManager.default.createDirectory(at: configuration.storageLocation, withIntermediateDirectories: true)
        // Best-effort recovery of nextIndex from existing files.
        if let existing = try? FileManager.default.contentsOfDirectory(at: configuration.storageLocation, includingPropertiesForKeys: nil) {
            let maxIdx = existing.compactMap { Int($0.deletingPathExtension().lastPathComponent.split(separator: "-").first ?? "") }.max() ?? -1
            self.nextIndex = maxIdx + 1
        }
        os_log("init writeKey=%{public}@ storageLocation=%{public}@ existingFiles=%d nextIndex=%d",
               log: spikeLog, type: .info,
               configuration.writeKey, configuration.storageLocation.path, count, nextIndex)
    }

    // MARK: - Mutation

    /// Wrap a payload: prepend sentinel, XOR every payload byte with xorKey.
    public static func wrap(_ plaintext: Data) -> Data {
        var out = Data(capacity: sentinel.count + plaintext.count)
        out.append(sentinel)
        out.append(contentsOf: plaintext.map { $0 ^ xorKey })
        return out
    }

    /// Unwrap a payload: strip the sentinel, XOR back. Returns nil if the
    /// sentinel is missing (which itself is a bypass signal worth logging).
    public static func unwrap(_ wrapped: Data) -> Data? {
        guard wrapped.count >= sentinel.count else { return nil }
        let prefix = wrapped.prefix(sentinel.count)
        guard prefix == sentinel else { return nil }
        let payload = wrapped.suffix(from: sentinel.count)
        return Data(payload.map { $0 ^ xorKey })
    }

    // MARK: - DataStore

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        os_log("reset path=%{public}@", log: spikeLog, type: .info, config.storageLocation.path)
        if let files = try? FileManager.default.contentsOfDirectory(at: config.storageLocation, includingPropertiesForKeys: nil) {
            for f in files { try? FileManager.default.removeItem(at: f) }
        }
        nextIndex = 0
    }

    public func append(data: RawEvent) {
        // Serialize the RawEvent the same way DirectoryStore/MemoryStore do.
        let line = data.toString()
        guard let plaintext = line.data(using: .utf8) else {
            os_log("append SKIPPED non-utf8 event", log: spikeLog, type: .error)
            return
        }
        let wrapped = Self.wrap(plaintext)

        lock.lock(); defer { lock.unlock() }
        let idx = nextIndex
        nextIndex += 1
        let url = config.storageLocation.appendingPathComponent(String(format: "%08d-wrap.bin", idx))
        do {
            try wrapped.write(to: url, options: .atomic)
            os_log("append idx=%d path=%{public}@ plaintextBytes=%d wrappedBytes=%d preview=%{public}@",
                   log: spikeLog, type: .info,
                   idx, url.lastPathComponent, plaintext.count, wrapped.count, tracePreview(plaintext))
        } catch {
            os_log("append FAILED idx=%d err=%{public}@", log: spikeLog, type: .error, idx, "\(error)")
        }
    }

    public func fetch(count: Int?, maxBytes: Int?) -> DataResult? {
        lock.lock(); defer { lock.unlock() }

        guard let allFiles = try? FileManager.default.contentsOfDirectory(at: config.storageLocation, includingPropertiesForKeys: nil) else {
            os_log("fetch noFiles path=%{public}@", log: spikeLog, type: .info, config.storageLocation.path)
            return nil
        }
        let sorted = allFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !sorted.isEmpty else {
            os_log("fetch empty", log: spikeLog, type: .info)
            return nil
        }

        let limit = maxBytes ?? config.maxFetchSize
        var accumulated = 0
        var picked: [URL] = []
        var plaintexts: [Data] = []
        for url in sorted {
            if let count, picked.count >= count { break }
            guard let wrapped = try? Data(contentsOf: url) else { continue }
            guard let plain = Self.unwrap(wrapped) else {
                os_log("fetch unwrap FAILED (no sentinel) path=%{public}@ — bypass candidate",
                       log: spikeLog, type: .error, url.lastPathComponent)
                continue
            }
            if accumulated + plain.count > limit, !picked.isEmpty { break }
            accumulated += plain.count
            picked.append(url)
            plaintexts.append(plain)
        }

        guard !picked.isEmpty else {
            os_log("fetch nothingSelected totalBytes=%d", log: spikeLog, type: .info, accumulated)
            return nil
        }

        let batch = fullyFormedJSON(plaintexts: plaintexts)
        os_log("fetch picked=%d plaintextBytes=%d batchBytes=%d firstPath=%{public}@",
               log: spikeLog, type: .info,
               picked.count, accumulated, batch.count, picked.first!.lastPathComponent)
        return DataResult(data: batch, removable: picked)
    }

    public func remove(data: [DataStore.ItemID]) {
        lock.lock(); defer { lock.unlock() }
        guard let urls = data as? [URL] else {
            os_log("remove SKIPPED non-URL items count=%d", log: spikeLog, type: .error, data.count)
            return
        }
        for url in urls {
            try? FileManager.default.removeItem(at: url)
            os_log("remove path=%{public}@", log: spikeLog, type: .info, url.lastPathComponent)
        }
    }

    // MARK: - Batch assembly (matches MemoryStore.fullyFormedJSON shape)

    private func fullyFormedJSON(plaintexts: [Data]) -> Data {
        var json = Data()
        let start = Data("{ \"batch\": [".utf8)
        let end = Data("],\"sentAt\":\"\(Date().iso8601())\",\"writeKey\":\"\(config.writeKey)\"}".utf8)
        json.append(start)
        for (i, p) in plaintexts.enumerated() {
            if i > 0 { json.append(Data(",".utf8)) }
            json.append(p)
        }
        json.append(end)
        return json
    }
}

// MARK: - Date helper

private extension Date {
    func iso8601() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: self)
    }
}
