import Foundation

/// Orders dwell diagnostics into `DwellDiagnosticJournal` without blocking or throwing to its caller.
/// Writes and clears run on one task chain, each awaiting the one before, so the journal sees them in
/// the order they were asked for; the journal actor does the storage I/O, off the main actor.
///
/// A generation separates identities. `invalidateAndClear` ends one at once and queues a clear behind
/// everything already queued. A record of an ended generation is dropped, whether still queued or late
/// with a token captured before an await. A clear is never dropped; a record is when the host has not
/// opted in or `maxPending` records are already queued.
@MainActor
final class DwellDiagnosticRecorder {
    static let maxPending = 128

    /// Shared with queued work, which still finishes against it once the recorder is released.
    @MainActor
    private final class State {
        var generation: UInt64 = 0
        var pendingRecords = 0
        /// Bound only: the identity records are kept for; nil while none is known.
        var owner: DwellDiagnosticOwner?
    }

    private let journal: DwellDiagnosticJournal
    private let isEnabled: Bool
    private let now: @MainActor () -> TimeInterval
    private let state: State
    private let identityProvider: (@MainActor () -> GeofenceIdentity?)?
    private var tail: Task<Void, Never>?

    /// Touches no storage. `now` reads uptime on `GeofenceClockReading.uptime`'s timeline. With an
    /// `identityProvider` the recorder is bound: its records belong to the identity that reports, none
    /// is kept while it reports none, and history kept for any other is cleared before the next write.
    init(
        journal: DwellDiagnosticJournal,
        isEnabled: Bool,
        now: @escaping @MainActor () -> TimeInterval,
        identityProvider: (@MainActor () -> GeofenceIdentity?)? = nil
    ) {
        self.journal = journal
        self.isEnabled = isEnabled
        self.now = now
        self.identityProvider = identityProvider
        self.state = State()
    }

    /// The current generation: capture it before an await whose outcome is recorded after it, so a
    /// reset or identity change during the await drops that record. Synced to the identity first, so
    /// a token read under a new identity never names the old one's generation.
    var token: UInt64 {
        syncIdentity()
        return state.generation
    }

    /// Bound only. When the identity in force is not the one records are kept for, ends the
    /// generation now, dropping the old identity's queued and captured records, and queues the
    /// journal's owner check, which clears history kept for any other. The same identity changes nothing.
    func syncIdentity() {
        guard let identityProvider else { return }
        let owner = identityProvider().flatMap { DwellDiagnosticOwner($0) }
        guard owner != state.owner else { return }
        state.owner = owner
        state.generation &+= 1
        guard isEnabled, let owner else { return }
        enqueue { [journal] in _ = await journal.prepareOwner(owner) }
    }

    /// Whether `entry` was queued: not when off, when `token` names an ended generation, when full, or
    /// when bound while no identity is known.
    @discardableResult
    func record(_ entry: DwellDiagnosticRecord, token: UInt64? = nil) -> Bool {
        syncIdentity()
        let generation = state.generation
        let owner = state.owner
        guard isEnabled, (token ?? generation) == generation, state.pendingRecords < Self.maxPending,
              identityProvider == nil || owner != nil
        else { return false }
        state.pendingRecords += 1
        enqueue { [state, journal] in
            defer { state.pendingRecords -= 1 }
            // Ended while queued: the clear or owner check queued behind it would only remove the write.
            guard state.generation == generation else { return }
            _ = await journal.append(entry, owner: owner)
        }
        return true
    }

    /// Builds the entry at `uptime`, or now, and queues it as `record(_:token:)` does. False also for
    /// an entry the record's bounds reject, such as one at a negative or non-finite uptime.
    @discardableResult
    func record(
        _ event: DwellDiagnosticEvent,
        at uptime: TimeInterval? = nil,
        token: UInt64? = nil,
        fenceId: String? = nil,
        deadlineUptime: TimeInterval? = nil,
        reason: DwellDiagnosticReason? = nil,
        requestedAccuracy: String? = nil,
        returnedAccuracy: Double? = nil,
        fixAge: TimeInterval? = nil
    ) -> Bool {
        guard isEnabled,
              let entry = DwellDiagnosticRecord(
                  event: event, atUptime: uptime ?? now(), fenceId: fenceId,
                  deadlineUptime: deadlineUptime, reason: reason, requestedAccuracy: requestedAccuracy,
                  returnedAccuracy: returnedAccuracy, fixAge: fixAge
              )
        else { return false }
        return record(entry, token: token)
    }

    /// Ends the current generation now and queues a clear behind everything already queued, even when
    /// off, since the stored history may predate an opt-out. Records queued after it are written after it.
    func invalidateAndClear() {
        state.generation &+= 1
        enqueue { [journal] in _ = await journal.clear() }
    }

    /// Waits for everything queued before the call. For focused tests and a diagnostics dump.
    func drain() async {
        await tail?.value
    }

    /// Each operation awaits the one before it. Captures no `self`, so queued work finishes once the
    /// recorder is released, holding only the journal and the shared state.
    private func enqueue(_ operation: @escaping @Sendable @MainActor () async -> Void) {
        let previous = tail
        tail = Task { @MainActor in
            await previous?.value
            await operation()
        }
    }
}
