import CioInternalCommon
import Foundation

/// The identity a queue request is made for, resolved the same way `GistQueueNetwork` picks the
/// user token header, within the generation started by the most recent logout.
struct QueueFetchKey: Equatable {
    let userToken: String
    let isAnonymous: Bool
    let generation: Int

    init?(state: InAppMessageState) {
        self.generation = state.queueFetchGeneration
        if let userId = state.userId, !userId.isBlankOrEmpty() {
            self.userToken = userId
            self.isAnonymous = false
        } else if let anonymousId = state.anonymousId, !anonymousId.isBlankOrEmpty() {
            self.userToken = anonymousId
            self.isAnonymous = true
        } else {
            return nil
        }
    }

    /// Stored next to the cached queue response, so a 304 only reuses a body fetched for this identity.
    var cacheOwner: String {
        "\(isAnonymous ? "anonymous" : "identified"):\(userToken)"
    }
}

/// Why a queue response was not applied.
enum QueueFetchError: Error {
    /// The identity changed while the request was in flight, so the response belongs to the previous one.
    case identityChanged
}

/// Lets queue fetches for the same identity share one request.
///
/// Several triggers fire within milliseconds of each other at launch (identity registration, the
/// store replaying `useSse` to a new subscriber, the foreground catch-up), and each used to send its
/// own request. While a request for an identity is in flight, later fetches for that identity reuse
/// it. A fetch that needs data from after it was requested (`mustBeFresh`) can't be answered by an
/// older request, so it schedules a single follow-up instead. gist-web guards its queue request the
/// same way.
final class QueueFetchCoordinator {
    struct Ticket: Equatable {
        let key: QueueFetchKey
        fileprivate let id: Int
    }

    private struct State {
        var inFlight: Ticket?
        var refetchWhenDone = false
        var nextId = 0
    }

    private let state = CioInternalCommon.Synchronized(State())

    /// Returns a ticket when the caller should send a request, or nil when a request for the same
    /// identity is already in flight.
    func begin(key: QueueFetchKey, mustBeFresh: Bool) -> Ticket? {
        state.mutating { state in
            if let inFlight = state.inFlight, inFlight.key == key {
                if mustBeFresh {
                    state.refetchWhenDone = true
                }
                return nil
            }

            // Nothing in flight, or a request for a previous identity whose response will be
            // discarded: start a new one.
            state.nextId += 1
            let ticket = Ticket(key: key, id: state.nextId)
            state.inFlight = ticket
            state.refetchWhenDone = false
            return ticket
        }
    }

    /// Releases the slot held by `ticket`. Returns true when a caller that needed newer data joined
    /// the request, so one follow-up fetch is owed.
    func finish(_ ticket: Ticket) -> Bool {
        state.mutating { state in
            // A request for another identity replaced this one; the slot is no longer ours.
            guard state.inFlight == ticket else { return false }

            let refetch = state.refetchWhenDone
            state.inFlight = nil
            state.refetchWhenDone = false
            return refetch
        }
    }
}
