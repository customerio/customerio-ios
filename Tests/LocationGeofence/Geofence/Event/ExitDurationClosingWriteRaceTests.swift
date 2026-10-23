@testable import CioInternalCommon
@testable import CioLocationGeofence
import CoreLocation
import Foundation
import SharedTests
import Testing

private let monitorAvailable: Bool = {
    if #available(iOS 17.0, *) { return true }
    return false
}()

/// Runs `onClose` once, from inside the storage job, on the first state write holding a visit for
/// `fenceId` closed by an observed boundary: before that job returns to the monitor awaiting it.
final class ClosingWriteProbe: FileManager, @unchecked Sendable {
    let fenceId: String
    private let lock = NSLock()
    private var onClose: (@Sendable () -> Void)?

    init(fenceId: String) {
        self.fenceId = fenceId
        super.init()
    }

    func arm(_ action: @escaping @Sendable () -> Void) {
        lock.lock()
        onClose = action
        lock.unlock()
    }

    override func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
        try super.setAttributes(attributes, ofItemAtPath: path)
        lock.lock()
        let action = onClose
        lock.unlock()
        guard let action, path.hasSuffix("geofenceState.json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path))
        else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard (try? decoder.decode(GeofenceState.self, from: data))?.dwellVisits?[fenceId]?.closedByObservedBoundary != nil
        else { return }
        lock.lock()
        onClose = nil
        lock.unlock()
        action()
    }
}

@MainActor
final class ReentryObservation {
    var beforeNote: Bool?
    var beforeRouting: Bool?
    var finished = false
}

/// Bugbot r4226788240 at the earliest start its window allows. A re-ENTER nothing proved is put on
/// the main actor from inside the storage job that records the stay's own EXIT and closes the
/// visit, so it is enqueued before `CLMonitor` resumes to hand that EXIT to the binder. Everything
/// after that is the runtime's own scheduling, through the real wrapper, storage, binder, resolver
/// and outbox. That EXIT still times the stay it closed, and the re-entry's visit survives.
/// Scheduling on this runtime: not a language guarantee, nor physical callback timing.
@Suite("GeofenceExitDurationClosingWriteRace", .serialized, .enabled(if: monitorAvailable))
@MainActor
struct ExitDurationClosingWriteRaceTests {
    private static let circle = DurableExitFences.circle

    @Test(arguments: [TaskPriority.high, .low])
    @available(iOS 17.0, *)
    func reentryStartedInsideTheClosingWriteLeavesTheClosingExitItsDuration(priority: TaskPriority) async throws {
        let device = DurableExitDevice()
        let probe = ClosingWriteProbe(fenceId: Self.circle.id)
        let process = await ExitDurationObservedBoundaryTests.process(on: device, fileManager: probe)
        defer { process.end() }
        process.route()
        let stay = try await ExitDurationObservedBoundaryTests.observedStay(process, device: device, fence: Self.circle)
        device.advance(60)
        let exitedAt = device.clock.wall
        let seen = ReentryObservation()
        let dwell = process.dwell
        probe.arm {
            Task(priority: priority) { @MainActor in
                seen.beforeNote = dwell.pendingExitCallbacks[Self.circle.id] == nil
                seen.beforeRouting = dwell.exitMarks[Self.circle.id] == nil
                device.advance(1)
                await dwell.handleBoundary(
                    geofence: Self.circle, transition: .enter, occurredAt: device.clock.wall,
                    expectedUserId: "user-a", crossingObserved: false, presenceProven: false
                )
                // Before any await: the replacement's own evidence request must not replace it in turn.
                dwell.cancelEvidence(for: Self.circle.id)
                seen.finished = true
            }
        }

        await process.deliver(.unsatisfied, to: Self.circle.id, at: exitedAt)
        #expect(await settleOnMain { seen.finished })
        for _ in 0 ..< 200 where await ExitDurationObservedBoundaryTests.exitRows(process).isEmpty {
            try? await Task.sleep(nanoseconds: 10000000)
        }

        // The re-ENTER started inside the window: before the binder noted or routed the EXIT.
        try #require(seen.beforeNote == true)
        #expect(seen.beforeRouting == true)
        let rows = await ExitDurationObservedBoundaryTests.exitRows(process)
        #expect(rows.count == 1)
        let row = try #require(rows.last)
        #expect(row.visitId == stay.visitId)
        #expect(row.enteredAt.map { Int($0.timeIntervalSince1970) } == Int(stay.enteredAt.timeIntervalSince1970))
        #expect(row.visitDurationSeconds == Int(exitedAt.timeIntervalSince1970) - Int(stay.enteredAt.timeIntervalSince1970))
        let survivor = try #require(await process.visit())
        #expect(survivor.visitId != stay.visitId)
        #expect(survivor.closedByObservedBoundary == nil)
        #expect(!survivor.entryObserved)
        #expect(await process.dwellRows().isEmpty)
    }
}
