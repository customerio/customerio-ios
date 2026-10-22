import CioInternalCommon
import Foundation

/// Lets a test await the nth occurrence of an event, including one that already happened.
/// Recorded from any thread; awaited without polling.
final class EventCounter: Sendable {
    private struct State {
        var count = 0
        var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    }

    private let state = Synchronized<State>(State())

    var count: Int {
        state.using { $0.count }
    }

    func record() {
        let ready = state.mutating { state -> [CheckedContinuation<Void, Never>] in
            state.count += 1
            let count = state.count
            let ready = state.waiters.filter { $0.count <= count }.map(\.continuation)
            state.waiters.removeAll { $0.count <= count }
            return ready
        }
        ready.forEach { $0.resume() }
    }

    func reached(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let resumeNow = state.mutating { state -> Bool in
                if state.count >= count { return true }
                state.waiters.append((count, continuation))
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }
}
