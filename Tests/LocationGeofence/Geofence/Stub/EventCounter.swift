import CioInternalCommon
import Foundation

/// Lets a test await the nth occurrence of an event, including one that already happened.
/// Recorded from any thread; awaited without polling.
final class EventCounter: Sendable {
    private struct Waiter {
        let id: UUID
        let count: Int
        let continuation: CheckedContinuation<Bool, Never>
    }

    private struct State {
        var count = 0
        var waiters: [Waiter] = []
    }

    private let state = Synchronized<State>(State())

    var count: Int {
        state.using { $0.count }
    }

    func record() {
        let ready = state.mutating { state -> [Waiter] in
            state.count += 1
            let count = state.count
            let ready = state.waiters.filter { $0.count <= count }
            state.waiters.removeAll { $0.count <= count }
            return ready
        }
        ready.forEach { $0.continuation.resume(returning: true) }
    }

    func reached(_ count: Int) async {
        _ = await wait(for: count, limit: nil)
    }

    /// `reached`, giving up after `limit` seconds so a regression fails instead of hanging. The
    /// limit only bounds a failure: a wait that succeeds resumes on the event itself.
    func reached(_ count: Int, within limit: TimeInterval) async -> Bool {
        await wait(for: count, limit: limit)
    }

    private func wait(for count: Int, limit: TimeInterval?) async -> Bool {
        let id = UUID()
        return await withCheckedContinuation { continuation in
            let resumeNow = state.mutating { state -> Bool in
                if state.count >= count { return true }
                state.waiters.append(Waiter(id: id, count: count, continuation: continuation))
                return false
            }
            if resumeNow { return continuation.resume(returning: true) }
            guard let limit else { return }
            Task { [state] in
                try? await Task.sleep(nanoseconds: UInt64(limit * 1000000000))
                let expired = state.mutating { state -> Waiter? in
                    guard let index = state.waiters.firstIndex(where: { $0.id == id }) else { return nil }
                    return state.waiters.remove(at: index)
                }
                expired?.continuation.resume(returning: false)
            }
        }
    }
}
