import CioInternalCommon
import Foundation

// MARK: - DI

extension DIGraphShared {
    /// Hand-written, like the resolvers': the recorder is `@MainActor`, and a background launch must
    /// reach it before `CustomerIO.initialize` has run.
    @MainActor
    var dwellDiagnosticRecorder: DwellDiagnosticRecorder {
        let overridden: DwellDiagnosticRecorder? = getOverriddenInstance()
        return overridden ?? DwellDiagnosticRecorder.shared
    }
}

extension DwellDiagnosticRecorder {
    /// One instance, so every writer shares one ordered chain into one journal. The opt-in is the main
    /// bundle's Info.plist, which a background launch reads without the SDK being initialized.
    @MainActor
    static let shared = DwellDiagnosticRecorder.make(
        isOptedIn: DwellDiagnosticJournal.isOptedIn(in: .main),
        directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
        // Read per use, so every writer, resolvers built before the coordinator included, records
        // under the identity in force.
        identityProvider: { DIGraphShared.shared.geofenceIdentityTracker.currentIdentity }
    )

    /// Timed on `SystemGeofenceClock` uptime, the timeline visits are measured on. Off (not opted in,
    /// or no Application Support directory) it records nothing, and history or an owner an opted-in
    /// build left is cleared once, here; with none there, it starts no task at all. On and bound, its
    /// first queued work is the owner check, so history kept for another identity is cleared ahead of
    /// every write, and of an export that drains first.
    @MainActor
    static func make(
        isOptedIn: Bool,
        directory: URL?,
        identityProvider: (@MainActor () -> GeofenceIdentity?)? = nil
    ) -> DwellDiagnosticRecorder {
        let enabled = isOptedIn && directory != nil
        let clock = SystemGeofenceClock()
        let recorder = DwellDiagnosticRecorder(
            journal: DwellDiagnosticJournal(
                directory: directory ?? FileManager.default.temporaryDirectory,
                isEnabled: { enabled }
            ),
            isEnabled: enabled,
            now: { clock.read().uptime },
            identityProvider: identityProvider
        )
        if enabled {
            recorder.syncIdentity()
        } else if let directory,
                  FileManager.default.fileExists(atPath: DwellDiagnosticJournal.storeDirectory(in: directory).path) {
            recorder.invalidateAndClear()
        }
        return recorder
    }
}
