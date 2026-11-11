@_spi(Internal) import CioInternalCommon
import Foundation

/// Persists receipts before the host completes its background callback. The queue is at least once;
/// retries preserve the original timestamp and target token, independent of the current profile.
/// A delivery gets one receipt: a repeat is skipped while its receipt is pending or was handled or sent this launch.
/// Nothing is sent until ``start(autoTrackPushEvents:)``, which `MessagingPush.initialize` calls with the app's config.
/// With automatic tracking off, nothing is ever sent and every saved receipt is removed.
final class BackgroundPushReceiptSender: @unchecked Sendable {
    static let maxUnsaved = 50
    static let maxHandledDeliveryIDs = 100

    private struct State {
        var task: Task<Void, Never>?
        var requested: UInt64 = 0
        var unsaved: [PendingPushDeliveryMetric] = []
        /// Deliveries given a receipt this launch, oldest first.
        var handledDeliveryIDs: [String] = []
        /// The app's `autoTrackPushEvents`, once `start` gives it. Until then receipts are saved, not sent.
        var tracking: Bool?
    }

    private let store: PendingPushDeliveryStore
    private let httpClient: BackgroundDeliveryHttpClient
    private let taskRunner: BackgroundTaskRunner
    private let logger: Logger
    /// Seconds on a monotonic clock, for the drain deadline.
    private let uptime: @Sendable () -> TimeInterval
    private let state = Synchronized(State())

    init(
        store: PendingPushDeliveryStore,
        httpClient: BackgroundDeliveryHttpClient,
        taskRunner: BackgroundTaskRunner,
        logger: Logger,
        uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.store = store
        self.httpClient = httpClient
        self.taskRunner = taskRunner
        self.logger = logger
        self.uptime = uptime
    }

    static func defaultFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("io.customer", isDirectory: true)
            .appendingPathComponent("background_push_receipts.json", isDirectory: false)
    }

    func enqueue(deliveryID: String, deviceToken: String, receivedAt: Date) {
        guard state.using({ $0.tracking }) != false else { return }
        let metric = PendingPushDeliveryMetric(deliveryId: deliveryID, deviceToken: deviceToken, event: .delivered, timestamp: receivedAt)
        // Checked and saved under one lock, so duplicates arriving together save one receipt.
        let isNew = state.mutating { s -> Bool in
            guard !s.handledDeliveryIDs.contains(deliveryID),
                  !store.loadAll().contains(where: { $0.deliveryId == deliveryID })
            else { return false }
            Self.remember(deliveryID, in: &s)
            if !store.append(metric) {
                logger.error("Background push receipt could not be saved; held in memory for this launch only")
                s.unsaved.append(metric)
                if s.unsaved.count > Self.maxUnsaved { s.unsaved.removeFirst(s.unsaved.count - Self.maxUnsaved) }
            }
            return true
        }
        if !isNew {
            logger.debug("Background push \(deliveryID) arrived again; its delivered receipt is already recorded")
        }
        // A repeat too: the first receipt may still be waiting after a failed send.
        scheduleDrain()
    }

    /// Starts sending, or with automatic tracking off, removes every saved receipt and never sends.
    func start(autoTrackPushEvents: Bool) {
        state.mutating { s in
            s.tracking = autoTrackPushEvents
            guard !autoTrackPushEvents else { return }
            s.unsaved = []
            guard case .rows(let rows) = store.read(), !rows.isEmpty else { return }
            if store.removeAll(ids: Set(rows.map(\.id))) {
                logger.info("Removed \(rows.count) background push receipts, as autoTrackPushEvents is off")
            }
        }
        scheduleDrain()
    }

    func scheduleDrain() {
        state.mutating { s in
            s.requested &+= 1
            guard s.tracking == true, s.task == nil else { return }
            guard !s.unsaved.isEmpty || !store.loadAll().isEmpty else { return }
            s.task = makeDrainTask()
        }
    }

    #if DEBUG
    func waitUntilIdle() async {
        while let task = state.using({ $0.task }) {
            await task.value
        }
    }
    #endif

    func observeContextReadiness(_ eventBus: EventBusHandler) {
        // DataPipeline publishes either event after installing its live API key provider.
        eventBus.addObserver(ProfileIdentifiedEvent.self) { [weak self] _ in self?.scheduleDrain() }
        eventBus.addObserver(AnonymousProfileIdentifiedEvent.self) { [weak self] _ in self?.scheduleDrain() }
    }

    private static func remember(_ deliveryID: String, in state: inout State) {
        guard !state.handledDeliveryIDs.contains(deliveryID) else { return }
        state.handledDeliveryIDs.append(deliveryID)
        if state.handledDeliveryIDs.count > maxHandledDeliveryIDs {
            state.handledDeliveryIDs.removeFirst(state.handledDeliveryIDs.count - maxHandledDeliveryIDs)
        }
    }

    private func makeDrainTask() -> Task<Void, Never> {
        Task.detached(priority: .utility) { [self] in
            await taskRunner.withBackgroundTime { await self.drainUntilIdle() }
        }
    }

    private func drainUntilIdle() async {
        // Start requests for at most five seconds; each HTTP request has a twenty-second resource timeout.
        let deadline = uptime() + 5
        while true {
            let seen = state.using { $0.requested }
            let drained = await drainOnce(deadline: deadline)
            let again = state.mutating { s -> Bool in
                guard s.requested != seen else { s.task = nil
                    return false
                }
                if drained, uptime() < deadline { return true }
                // A push arriving during a failed send gets one fresh background-time window.
                s.task = makeDrainTask()
                return false
            }
            if !again { return }
        }
    }

    /// Sends saved receipts in order. Returns false, ending this pass, on a retryable error or at the deadline.
    private func drainOnce(deadline: TimeInterval) async -> Bool {
        for metric in state.using({ $0.unsaved }) {
            guard uptime() < deadline, await finish(metric) else { return false }
            state.mutating { $0.unsaved.removeAll { $0.id == metric.id } }
        }
        guard case .rows(let rows) = store.read() else { return false }
        for metric in rows {
            guard uptime() < deadline, await finish(metric) else { return false }
            // A row saved by an earlier launch: a repeat of its push this launch gets no new receipt.
            state.mutating { Self.remember(metric.deliveryId, in: &$0) }
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
