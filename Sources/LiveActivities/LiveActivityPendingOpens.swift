import CioLiveActivities_Attributes
import Foundation

final class LiveActivityPendingOpens {
    private let limit: Int
    private var buffered: [CIOLiveActivityMetadata] = []
    private let lock = NSLock()

    init(limit: Int = 10) {
        self.limit = limit
    }

    func append(_ metadata: CIOLiveActivityMetadata) {
        lock.lock()
        defer { lock.unlock() }
        buffered.append(metadata)
        if buffered.count > limit {
            buffered.removeFirst(buffered.count - limit)
        }
    }

    func drain() -> [CIOLiveActivityMetadata] {
        lock.lock()
        defer { lock.unlock() }
        let drained = buffered
        buffered = []
        return drained
    }
}
