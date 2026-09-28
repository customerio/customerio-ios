import CioInternalCommon
import CoreLocation
import Foundation

@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    /// A sleep, not a `Timer`: an overdue sleep resumes on the next slice of runtime. A `mirror_beat`
    /// with no `condition_mirror` after it means the monitor pipeline is wedged.
    func startConditionMirrorSampling() {
        guard GeofenceDiagnostics.isEnabled else { return }
        Task { [weak self] in
            // Monotonic: `Date()` steps under NTP. This also counts suspended time, which `since`
            // measures.
            var previousBeatAt = GeofenceLog.monotonicNow()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.conditionMirrorSampleNanos)
                // `try?` swallows the sleep's cancellation, so without this the body runs once more.
                if Task.isCancelled { return }
                guard let self else { return }
                let beatAt = GeofenceLog.monotonicNow()
                // Read once so both records report the same `want`.
                let wanted = self.conditionLedger.stagedIdentifiers
                // Not `condition_mirror_beat`: `grep why=condition_mirror` would then match both.
                self.logger.geofenceInfo("mirror_beat", fields: [
                    ("since", String(Int((beatAt - previousBeatAt).rounded()))),
                    ("want", String(wanted.count))
                ])
                previousBeatAt = beatAt
                self.logConditionMirrorDrift(desired: wanted, at: .poll)
            }
        }
    }

    /// `desired` must be captured in the turn that enqueues the OS work it describes, never live
    /// ownership: later syncs mutate ownership while their OS work is still queued.
    func logConditionMirrorDrift(desired: Set<String>, refused: Int = 0, at occasion: ConditionMirrorOccasion) {
        guard GeofenceDiagnostics.isEnabled else { return }
        // Captured with `desired`, not at drain, so both describe the same instant.
        let owned = ownedRegionIdentifiers.count
        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            let drift = ConditionMirror.drift(desired: desired, atOs: Set(await monitor.identifiers))
            self.logger.geofenceInfo("condition_mirror", fields: [
                ("at", occasion.token),
                ("want", String(desired.count)),
                // Omitted when zero; always absent on a sample.
                ("refused", refused > 0 ? String(refused) : nil),
                // Equals `want` on `sync`. On `poll`, an owned condition never staged this process
                // reads as `extra` until a sync re-registers it.
                ("owned", String(owned)),
                ("os", String(drift.atOsCount)),
                // Not a raw join: workspace-authored identifiers can contain commas. `missing` never
                // shows a condition the OS gave up on; it stays listed (see `.unmonitored`).
                ("missing", GeofenceLog.list(drift.missing)),
                ("extra", GeofenceLog.list(drift.extra))
            ])
        }
    }

    static let conditionMirrorSampleNanos: UInt64 = 120000000000
}

enum ConditionMirror {
    /// Ownership is taken only once `startMonitoring`'s guards pass, so after `setMonitoredRegions`
    /// `desired` ∩ ownership is the accepted subset.
    struct Target: Equatable {
        let accepted: Set<String>
        let refused: Int
    }

    static func target(desired: Set<String>, owned: Set<String>) -> Target {
        let accepted = desired.intersection(owned)
        return Target(accepted: accepted, refused: desired.count - accepted.count)
    }

    struct Drift: Equatable {
        let missing: [String]
        let extra: [String]
        let atOsCount: Int
    }

    static func drift(desired: Set<String>, atOs: Set<String>) -> Drift {
        Drift(
            missing: desired.subtracting(atOs).sorted(),
            extra: atOs.subtracting(desired).sorted(),
            atOsCount: atOs.count
        )
    }
}

@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    func persistConditionMirror() {
        userDefaults.set(knownConditionIdentifiers.sorted(), forKey: Self.conditionMirrorKey)
    }
}
