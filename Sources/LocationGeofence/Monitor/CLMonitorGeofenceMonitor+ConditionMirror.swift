import CioInternalCommon
import CoreLocation
import Foundation

/// The `condition_mirror` probe: what the OS actually holds, against what this process asked it to
/// hold.
@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    /// Samples the probe on a timer too, because a sync-time record cannot observe the failure it
    /// exists for: syncs only run off wakes, and the failure is the absence of wakes (the process
    /// alive, but no region callbacks arriving).
    ///
    /// A sleep, not a `Timer`: neither runs while suspended, but an overdue sleep resumes on the next
    /// slice of runtime the process gets. The interval is a floor, never a guarantee.
    ///
    /// Each sample emits two records. `mirror_beat` is written here; `condition_mirror` runs on the
    /// serial monitor pipeline, the only place `CLMonitor.identifiers` is reachable. Beats without
    /// comparisons mean the pipeline is wedged by an operation that suspends forever. A wedge that
    /// blocks the MainActor synchronously stops both and cannot be told apart this way.
    func startConditionMirrorSampling() {
        guard GeofenceDiagnostics.isEnabled else { return }
        Task { [weak self] in
            // Monotonic: `Date()` steps under NTP and would print a negative or inflated gap. On
            // Darwin it also counts while suspended, which is the interval being measured.
            var previousBeatAt = GeofenceLog.monotonicNow()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.conditionMirrorSampleNanos)
                // `try?` swallows the sleep's cancellation, so without this the body runs once more.
                if Task.isCancelled { return }
                guard let self else { return }
                let beatAt = GeofenceLog.monotonicNow()
                // Read once so both records report the same `want`. The ledger, not a sync's
                // `desired` set: a sample belongs to no sync.
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

    /// Records what CLMonitor itself holds against `desired`. Other registration records report
    /// ownership, i.e. our own belief, never what the OS holds.
    ///
    /// `desired` is a value captured in the same turn that enqueues the OS work it describes, never
    /// live ownership: later syncs mutate ownership synchronously while their OS work is still
    /// queued, which would read as drift. A sync passes its accepted set; the sampler passes the
    /// ledger's staged identifiers.
    ///
    /// `owned` is logged too. On `at=sync` it equals `want` by construction, so a gap there is a bug
    /// in this monitor. On `at=poll` a gap is expected at process start: the ledger starts empty but
    /// ownership does not, so an owned condition this process never staged reads as `extra` until a
    /// sync re-registers it.
    ///
    /// `refused` is the only record of how many regions `startMonitoring` turned down (blocked
    /// permission, unusable coordinates); keeping them out of `desired` stops them showing as
    /// `missing`, which would blame the OS.
    ///
    /// `missing` does not catch a condition the OS gave up on: it stays listed in
    /// `CLMonitor.identifiers`. That case logs from the `.unmonitored` branch in
    /// `process(event:)`.
    func logConditionMirrorDrift(desired: Set<String>, refused: Int = 0, at occasion: ConditionMirrorOccasion) {
        // Diagnostics-only, so don't queue the operation below ahead of real monitor work.
        guard GeofenceDiagnostics.isEnabled else { return }
        // Captured with `desired`, not at drain, so both describe the same instant.
        let owned = ownedRegionIdentifiers.count
        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            // Drains after this sync's own adds and removes, so the OS should hold exactly
            // `desired` by now.
            let drift = ConditionMirror.drift(desired: desired, atOs: Set(await monitor.identifiers))
            self.logger.geofenceInfo("condition_mirror", fields: [
                ("at", occasion.token),
                ("want", String(desired.count)),
                // Omitted when zero, so the key's presence is the signal. Always absent on a sample.
                ("refused", refused > 0 ? String(refused) : nil),
                ("owned", String(owned)),
                ("os", String(drift.atOsCount)),
                // `GeofenceLog.list` sanitizes workspace-authored identifiers and caps the list; a
                // raw join would let an identifier's own commas split or merge tokens.
                ("missing", GeofenceLog.list(drift.missing)),
                ("extra", GeofenceLog.list(drift.extra))
            ])
        }
    }

    /// Floor on the sampling interval (2 min): a handful of records per drive, while a silent window
    /// of several minutes is still sampled repeatedly.
    static let conditionMirrorSampleNanos: UInt64 = 120000000000
}

/// The `condition_mirror` comparison, kept off the monitor so it carries no `@available` gate and
/// is testable on its own.
enum ConditionMirror {
    /// What a sync actually asked the OS to hold, and how much of its request was refused.
    ///
    /// Ownership is taken only once both of `startMonitoring`'s guards pass, so at the end of
    /// `setMonitoredRegions` the intersection of `desired` and ownership is the accepted subset.
    /// `refused` keeps a blocked-permission sync from producing a clean-looking record.
    ///
    /// The sampler needs no equivalent: both refusal returns in `startMonitoring` come before
    /// `noteRegisteredCondition`, and a re-registration retires the ledger entry first, so
    /// `stagedIdentifiers` is already the accepted set.
    struct Target: Equatable {
        let accepted: Set<String>
        let refused: Int
    }

    static func target(desired: Set<String>, owned: Set<String>) -> Target {
        let accepted = desired.intersection(owned)
        return Target(accepted: accepted, refused: desired.count - accepted.count)
    }

    /// Sorted so a capture diffs cleanly across passes.
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
    /// Writes the UserDefaults mirror of `knownConditionIdentifiers` that `init` seeds from.
    func persistConditionMirror() {
        userDefaults.set(knownConditionIdentifiers.sorted(), forKey: Self.conditionMirrorKey)
    }
}
