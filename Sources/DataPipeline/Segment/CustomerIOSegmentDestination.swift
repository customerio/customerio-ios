import CioInternalCommon
import Foundation
import Segment
import Sovran

#if os(Linux)
// Whoever is doing swift/linux development over there
// decided that it'd be a good idea to split out a TON
// of stuff into another framework that NO OTHER PLATFORM
// has; I guess to be special.  :man-shrugging:
import FoundationNetworking
#endif

// Based on upstream commit 35b6ec8f4e1833b3973342b85747017826db8dbb
public class CustomerIODestination: DestinationPlugin, Subscriber, FlushCompletion {
    enum Constants: String {
        case integrationName = "Segment.io"
        case apiHost
        case apiKey
    }

    public let type = PluginType.destination
    public let key: String = Constants.integrationName.rawValue
    public let timeline = Timeline()
    public weak var analytics: Analytics? {
        didSet {
            initialSetup()
        }
    }

    struct UploadTaskInfo {
        let url: URL
        let task: URLSessionDataTask
        // set/used via an extension in iOSLifecycleMonitor.swift
        typealias CleanupClosure = () -> Void
        var cleanup: CleanupClosure?
    }

    private var writeKey: String {
        DataPipeline.moduleConfig.cdpApiKey
    }

    var httpClient: HTTPClient?
    private var uploads = [UploadTaskInfo]()
    private let uploadsQueue = DispatchQueue(label: "uploadsQueue.segment.com")
    private var storage: Storage?

    @Atomic var eventCount: Int = 0

    func initialSetup() {
        guard let analytics = analytics else { return }
        storage = Storage(writeKey: writeKey)
        httpClient = HTTPClient()

        // TODO: Not sure if we need this?
        // Add DestinationMetadata enrichment plugin
//        add(plugin: DestinationMetadataPlugin())
    }

    public func update(settings: Settings, type: UpdateType) {
        guard let analytics = analytics else { return }
        let segmentInfo = settings.integrationSettings(forKey: key)
    }

    // MARK: - Event Handling Methods

    public func execute<T: RawEvent>(event: T?) -> T? {
        guard let event = event else { return nil }
        let result = process(incomingEvent: event)
        if let r = result {
            queueEvent(event: r)
        }
        return result
    }

    // MARK: - Abstracted Lifecycle Methods

    func enterForeground() {}

    func enterBackground() {
        flush()
    }

    // MARK: - Event Parsing Methods

    private func queueEvent<T: RawEvent>(event: T) {
        guard let storage = storage else { return }
        // Send Event to File System
        storage.write(.events, value: event)
        eventCount += 1
    }

    public func flush() {
        // unused .. see flush(group:completion:)
    }

    public func flush(group: DispatchGroup, completion: @escaping (DestinationPlugin) -> Void) {
        guard let storage = storage else { return }
        guard let analytics = analytics else { return }
        guard let httpClient = httpClient else { return }

        // don't flush if analytics is disabled.
        guard analytics.enabled == true else { return }

        // enter for the high level flush, allow us time to run through any existing files..
        group.enter()

        // Read events from file system
        guard let data = storage.read(Storage.Constants.events) else { group.leave()
            return
        }

        eventCount = 0
        cleanupUploads()

        analytics.log(message: "Uploads in-progress: \(pendingUploads)")

        if pendingUploads == 0 {
            for url in data {
                // enter for this url we're going to kick off
                group.enter()
                analytics.log(message: "Processing Batch:\n\(url.lastPathComponent)")
                // set up the task
                let uploadTask = httpClient.startBatchUpload(writeKey: writeKey, batch: url) { result in
                    switch result {
                    case .success:
                        storage.remove(file: url)
                        self.cleanupUploads()

                    // we don't want to retry events in a given batch when a 400
                    // response for malformed JSON is returned
                    case .failure(Segment.HTTPClientErrors.statusCode(code: 400)):
                        storage.remove(file: url)
                        self.cleanupUploads()
                    default:
                        break
                    }

                    analytics.log(message: "Processed: \(url.lastPathComponent)")
                    // the upload we have here has just finished.
                    // make sure it gets removed and it's cleanup() called rather
                    // than waiting on the next flush to come around.
                    self.cleanupUploads()
                    // call the completion
                    completion(self)
                    // leave for the url we kicked off.
                    group.leave()
                }
                // we have a legit upload in progress now, so add it to our list.
                if let upload = uploadTask {
                    add(uploadTask: UploadTaskInfo(url: url, task: upload))
                }
            }
        } else {
            analytics.log(message: "Skipping processing; Uploads in progress.")
        }

        // leave for the high level flush
        group.leave()
    }
}

// MARK: - Upload management

extension CustomerIODestination {
    func cleanupUploads() {
        // lets go through and get rid of any tasks that aren't running.
        // either they were suspended because a background task took too
        // long, or the os orphaned it due to device constraints (like a watch).
        uploadsQueue.sync {
            let before = uploads.count
            var newPending = uploads
            newPending.removeAll { uploadInfo in
                let shouldRemove = uploadInfo.task.state != .running
                if shouldRemove, let cleanup = uploadInfo.cleanup {
                    cleanup()
                }
                return shouldRemove
            }
            uploads = newPending
            let after = uploads.count
            analytics?.log(message: "Cleaned up \(before - after) non-running uploads.")
        }
    }

    var pendingUploads: Int {
        var uploadsCount = 0
        uploadsQueue.sync {
            uploadsCount = uploads.count
        }
        return uploadsCount
    }

    func add(uploadTask: UploadTaskInfo) {
        uploadsQueue.sync {
            uploads.append(uploadTask)
        }
    }
}

// MARK: Versioning

extension CustomerIODestination: VersionedPlugin {
    public static func version() -> String {
        SdkVersion.version
    }
}
