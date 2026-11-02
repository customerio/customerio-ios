@_spi(Internal) import CioInternalCommon
import Foundation

/// Persists receipts before the host completes its background callback. The queue is at least once;
/// retries preserve the original timestamp and target token, independent of the current profile.
final class BackgroundPushReceiptSender: @unchecked Sendable {
    static let fileName = "background_push_receipts.json"
    static let maxUnsaved = 50

    private struct State {
        var task: Task<Void, Never>?
        var requested: UInt64 = 0
        var unsaved: [PendingPushDeliveryMetric] = []
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
        if !store.append(metric) {
            logger.error("Background push receipt could not be saved; held in memory for this launch only")
            state.mutating { s in
                s.unsaved.append(metric)
                if s.unsaved.count > Self.maxUnsaved { s.unsaved.removeFirst(s.unsaved.count - Self.maxUnsaved) }
            }
        }
        scheduleDrain()
    }

    func scheduleDrain() {
        state.mutating { s in
            s.requested &+= 1
            guard s.task == nil else { return }
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
