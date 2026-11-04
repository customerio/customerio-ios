@_spi(Internal) import CioInternalCommon
import Foundation

/// Persists receipts before the host completes its background callback. The queue is at least once;
/// retries preserve the original timestamp and target token, independent of the current profile.
/// A delivery gets one receipt: a repeat is skipped while its receipt is pending or was handled this launch.
/// Nothing is sent until ``start(autoTrackPushEvents:)``, which `MessagingPush.initialize` calls with the app's config.
final class BackgroundPushReceiptSender: @unchecked Sendable {
    static let fileName = "background_push_receipts.json"
    static let maxUnsaved = 50
    static let maxHandledDeliveryIDs = 100

    private struct State {
        var task: Task<Void, Never>?
        var requested: UInt64 = 0
        var unsaved: [PendingPushDeliveryMetric] = []
        /// Deliveries given a receipt this launch, oldest first.
        var handledDeliveryIDs: [String] = []
        var started = false
        /// Receipts saved before `start`, when it wasn't yet known whether the app tracks automatically.
        var earlyReceiptIDs: [UUID] = []
    }

    private let store: PendingPushDeliveryStore
    private let httpClient: BackgroundDeliveryHttpClient
    private let taskRunner: BackgroundTaskRunner
    private let logger: Logger
    private let state = Synchronized(State())

    init(store: PendingPushDeliveryStore, httpClient: BackgroundDeliveryHttpClient, taskRunner: BackgroundTaskRunner, logger: Logger) {
        self.store = store
        self.httpClient = httpClient
        self.taskRunner = taskRunner
        self.logger = logger
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("io.customer", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    func enqueue(deliveryID: String, deviceToken: String, receivedAt: Date) {
        let metric = PendingPushDeliveryMetric(deliveryId: deliveryID, deviceToken: deviceToken, event: .delivered, timestamp: receivedAt)
        // Checked and saved under one lock, so duplicates arriving together save one receipt.
        let isNew = state.mutating { s -> Bool in
            guard !s.handledDeliveryIDs.contains(deliveryID),
                  !store.loadAll().contains(where: { $0.deliveryId == deliveryID })
            else { return false }
            s.handledDeliveryIDs.append(deliveryID)
            if s.handledDeliveryIDs.count > Self.maxHandledDeliveryIDs {
                s.handledDeliveryIDs.removeFirst(s.handledDeliveryIDs.count - Self.maxHandledDeliveryIDs)
            }
            if !store.append(metric) {
                logger.error("Background push receipt could not be saved; held in memory for this launch only")
                s.unsaved.append(metric)
                if s.unsaved.count > Self.maxUnsaved { s.unsaved.removeFirst(s.unsaved.count - Self.maxUnsaved) }
            }
            if !s.started { s.earlyReceiptIDs.append(metric.id) }
            return true
        }
        if !isNew {
            logger.debug("Background push \(deliveryID) arrived again; its delivered receipt is already recorded")
        }
        // A repeat too: the first receipt may still be waiting after a failed send.
        scheduleDrain()
    }

    /// Starts sending. With automatic tracking off, receipts saved before this are removed unsent.
    func start(autoTrackPushEvents: Bool) {
        state.mutating { s in
            let early = s.earlyReceiptIDs
            if !autoTrackPushEvents, !early.isEmpty {
                early.forEach { _ = store.remove(id: $0) }
                s.unsaved.removeAll { early.contains($0.id) }
                logger.info("Removed \(early.count) background push receipts saved before initialization, as autoTrackPushEvents is off")
            }
            s.earlyReceiptIDs = []
            s.started = true
        }
        scheduleDrain()
    }

    func scheduleDrain() {
        state.mutating { s in
            s.requested &+= 1
            guard s.started, s.task == nil else { return }
            guard !s.unsaved.isEmpty || !store.loadAll().isEmpty else { return }
            s.task = makeDrainTask()
        }
    }

    func waitUntilIdle() async {
        while let task = state.using({ $0.task }) {
            await task.value
        }
    }

    func observeContextReadiness(_ eventBus: EventBusHandler) {
        // DataPipeline publishes either event after installing its live API key provider.
        eventBus.addObserver(ProfileIdentifiedEvent.self) { [weak self] _ in self?.scheduleDrain() }
        eventBus.addObserver(AnonymousProfileIdentifiedEvent.self) { [weak self] _ in self?.scheduleDrain() }
    }

    private func makeDrainTask() -> Task<Void, Never> {
        Task.detached(priority: .utility) { [self] in
            await taskRunner.withBackgroundTime { await self.drainUntilIdle() }
        }
    }

    private func drainUntilIdle() async {
        // Start requests for at most five seconds; each HTTP request has a twenty-second resource timeout.
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while true {
            let seen = state.using { $0.requested }
            let drained = await drainOnce(deadline: deadline)
            let again = state.mutating { s -> Bool in
                guard s.requested != seen else { s.task = nil
                    return false
                }
                if drained, ProcessInfo.processInfo.systemUptime < deadline { return true }
                // A push arriving during a failed send gets one fresh background-time window.
                s.task = makeDrainTask()
                return false
            }
            if !again { return }
        }
    }

    /// A retryable error ends this wake's work, including requests arriving while offline.
    private func drainOnce(deadline: TimeInterval) async -> Bool {
        for metric in state.using({ $0.unsaved }) {
            guard ProcessInfo.processInfo.systemUptime < deadline, await finish(metric) else { return false }
            state.mutating { $0.unsaved.removeAll { $0.id == metric.id } }
        }
        guard case .rows(let rows) = store.read() else { return false }
        for metric in rows {
            guard ProcessInfo.processInfo.systemUptime < deadline, await finish(metric) else { return false }
            guard store.remove(id: metric.id) else {
                logger.error("Background push receipt could not be removed after sending; it may be sent again")
                return false
            }
        }
        return true
    }

    private func finish(_ metric: PendingPushDeliveryMetric) async -> Bool {
        let request = BackgroundTrackRequest(
            eventName: "Report Delivery Event",
            anonymousId: metric.deliveryId,
            properties: ["recipient": metric.deviceToken, "metric": metric.event.rawValue, "deliveryId": metric.deliveryId],
            timestamp: metric.timestamp
        )
        let result = await withCheckedContinuation { continuation in
            httpClient.sendTrackEvent(request) { continuation.resume(returning: $0) }
        }
        switch result {
        case .success:
            return true
        case .failure(.http(let code)) where (400 ..< 500).contains(code) && ![401, 403, 408, 429].contains(code):
            logger.error("Background push receipt was permanently rejected with HTTP \(code)")
            return true
        case .failure(let error):
            logger.info("Background push receipt retained for retry: \(error)")
            return false
        }
    }
}
