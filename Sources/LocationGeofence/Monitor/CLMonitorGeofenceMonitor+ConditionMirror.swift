import CioInternalCommon
import CoreLocation
import Foundation

/// The `condition_mirror` probe: what the OS actually holds, against what this process asked it to
/// hold. Split from `+Registration` so both stay under the file cap; `internal` rather than
/// `private` only because of that split.
@available(iOS 17.0, *)
extension CLMonitorGeofenceMonitor {
    /// Samples the mirror on a slow timer as well, because the sync-time record cannot observe
    /// the failure it was written for: a record is only emitted by `setMonitoredRegions`, a sync
    /// only runs off a wake, and the failure IS the absence of wakes. Measured 09-17: the last
    /// reading landed ten seconds before region callbacks stopped and the next came two hours
    /// later, across a window where the process was demonstrably alive and taking visit callbacks.
    ///
    /// A sleep rather than a `Timer`: neither runs while the process is suspended, but an overdue
    /// sleep resumes on the next slice of runtime something else earns us — which is exactly when a
    /// sample is worth taking, and the only time one is possible. So the cadence below is a floor
    /// on the interval, never a guarantee, and a silent window yields as many samples as the
    /// process happened to be woken for.
    ///
    /// Each sample emits TWO records, and the split is the point. The beat is written synchronously
    /// here; the comparison against the OS has to run on the monitor pipeline, because
    /// `CLMonitor.identifiers` is only reachable from there. That pipeline is strictly serial, so
    /// one operation that never returns — or a `CLMonitor` that never finishes loading — silences
    /// every operation behind it, samples included. Region callbacks are read off the same actor,
    /// which makes "the pipeline is wedged" a candidate explanation for the exact 09-17 signature:
    /// process alive, visit callbacks arriving, region callbacks stopped. Beats without
    /// comparisons is that diagnosis; a probe reporting only through the pipeline could never
    /// make it.
    ///
    /// Read as ONE wedge shape, not as the wedge. Both halves are `@MainActor`, so the split
    /// separates a wedge that SUSPENDS — a monitor call awaiting forever, leaving the MainActor
    /// free and the beats coming — from a healthy process. It cannot separate one that blocks the
    /// MainActor synchronously, where nothing runs and the capture looks the same as suspension.
    /// And both records are `debug`, so a host logging at `.info` has neither of them rather than
    /// fewer of one: the beat-to-comparison ratio is only readable where the pair is.
    ///
    /// The task is process-lifetime by construction — the monitor is held in a `static let`, so
    /// `[weak self]` is the correct capture but never actually fires outside tests.
    func startConditionMirrorSampling() {
        guard GeofenceDiagnostics.isEnabled else { return }
        Task { [weak self] in
            // Monotonic, like every other elapsed value in the module: `Date()` steps under NTP
            // and would print a negative or wildly inflated gap in the one record whose entire job
            // is to be trusted about a gap. On Darwin it also counts while the process is
            // suspended, which is the interval being measured.
            var previousBeatAt = GeofenceLog.monotonicNow()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.conditionMirrorSampleNanos)
                // `try?` swallows the cancellation a sleep throws, and the sleep is the first
                // statement in the body, so without this the body runs once more on teardown.
                if Task.isCancelled { return }
                guard let self else { return }
                let beatAt = GeofenceLog.monotonicNow()
                // Read once for both records. Identical today because nothing between them
                // suspends, but hoisting makes that structural: paired records reporting two
                // different `want` values would read as drift that never happened.
                //
                // The ledger, not the last `desired` set: a sample belongs to no sync generation,
                // and `stagedIdentifiers` is the standing answer to what this process wants held.
                let wanted = self.conditionLedger.stagedIdentifiers
                // `mirror_beat`, deliberately not `condition_mirror_beat`: the diagnosis is a
                // count of beats against a count of comparisons, and a name that prefixes the
                // other record's would make `grep why=condition_mirror` merge the two silently.
                self.logger.geofenceInfo("mirror_beat", fields: [
                    ("since", String(Int((beatAt - previousBeatAt).rounded()))),
                    ("want", String(wanted.count))
                ])
                previousBeatAt = beatAt
                self.logConditionMirrorDrift(desired: wanted, at: .poll)
            }
        }
    }

    /// Records what CLMonitor itself holds against what THIS sync asked it to hold.
    ///
    /// Every registration record until now asserted our own belief: `monitoredRegionIdentifiers`
    /// returns `ownedRegionIdentifiers`, so `registration.adopted n=13` means "we think thirteen",
    /// never "the OS holds thirteen".
    ///
    /// `desired` is a captured value, never ownership. Ownership is the wrong side to compare: it
    /// is mutated synchronously by any later `setMonitoredRegions` whose OS work is still queued
    /// behind this record, and unioned into by `reconcileKnownConditions` on the first pipeline
    /// operation — so an ownership-based comparison reports healthy staged changes as drift in one
    /// direction or the other, whichever end it is read from. A sync passes its own set; the
    /// sampler passes the ledger's staged identifiers, which is the standing form of the same
    /// question. Both are read in the same synchronous turn that enqueues the OS work they
    /// describe, so the comparison below drains behind that work either way.
    ///
    /// `owned` rides alongside `want` because the two baselines disagree at process start and the
    /// difference is diagnostic, not noise: the ledger begins each process empty while ownership
    /// does not, so a condition the OS holds and we own, but which this process never staged —
    /// an adopted record with no geometry, or the `userChangedDuringBootstrap` branch — reads as
    /// `extra` on every sample until a sync re-registers it. With `owned` present a reader can
    /// tell that from "the OS is holding something nobody wants".
    ///
    /// Read the gap with `at`, because the two occasions differ. On `at=poll` it is the
    /// process-start divergence above. On `at=sync` the two are equal by construction — the
    /// caller passes `ConditionMirror.accepted`, which is `desired` intersected with ownership —
    /// so a divergence there is not a finding about the OS but a broken invariant in this file.
    /// Refused registrations are why that scoping exists, and they have their own records.
    ///
    /// `missing` is therefore precisely "this sync asked the OS for it and the OS does not list
    /// it". It is NOT a general "monitored by nobody" test: a condition the OS GAVE UP on stays
    /// listed in `CLMonitor.identifiers` (measured) and so never appears here. That case has its
    /// own record, from the `.unmonitored` branch in `process(event:)`; read the two together.
    func logConditionMirrorDrift(desired: Set<String>, at occasion: ConditionMirrorOccasion) {
        // Diagnostics-only work must cost normal users nothing. `geofenceInfo` drops the tail when
        // diagnostics are off, but the actor hop and set arithmetic below would still be queued on
        // the registration FIFO ahead of real monitor operations.
        guard GeofenceDiagnostics.isEnabled else { return }
        // Captured here, alongside `desired`, rather than read inside the operation: ownership is
        // mutated synchronously by any later sync, so a drain-time read would put two instants in
        // one record and show a want/owned divergence for a cause this record's own doc rules out.
        let owned = ownedRegionIdentifiers.count
        enqueueMonitorOperation { [weak self] monitor in
            guard let self else { return }
            // Drains after this sync's own adds and removes, so the OS should hold exactly
            // `desired` by now.
            let drift = ConditionMirror.drift(desired: desired, atOs: Set(await monitor.identifiers))
            self.logger.geofenceInfo("condition_mirror", fields: [
                ("at", occasion.token),
                ("want", String(desired.count)),
                ("owned", String(owned)),
                ("os", String(drift.atOsCount)),
                // `GeofenceLog.list`, not a plain join: these name conditions, and an identifier is
                // workspace-authored. The helper sanitizes each one and caps the list, where a raw
                // join would have the tail fold its own commas and turn two into one token.
                ("missing", GeofenceLog.list(drift.missing)),
                ("extra", GeofenceLog.list(drift.extra))
            ])
        }
    }

    /// Floor on the sampling interval. Long enough that a drive costs a handful of records rather
    /// than one per fix, short enough that an 18-minute silent window is sampled repeatedly.
    static let conditionMirrorSampleNanos: UInt64 = 120000000000
}

/// The `condition_mirror` comparison, kept off the monitor so it carries no `@available` gate and
/// can be tested without a `CLMonitor` — which cannot be instantiated in a unit test.
enum ConditionMirror {
    /// What a sync actually asked the OS to hold: its desired set minus everything
    /// `startMonitoring` refused.
    ///
    /// Ownership is the record of acceptance — it is inserted only once both guards pass, and
    /// `setMonitoredRegions` has already released it for every identifier it no longer wants, so
    /// at the end of that loop ownership is exactly the accepted subset of `desired`. Intersecting
    /// rather than reading ownership directly keeps that a stated relationship instead of a
    /// coincidence, and keeps a refusal out of `missing` even if ownership later grows a member
    /// the desired set never had.
    ///
    /// The sampler needs no equivalent: `startMonitoring` returns before `noteRegisteredCondition`
    /// on both refusal paths, so a refused identifier never enters the ledger and `stagedIdentifiers`
    /// has always been the accepted set.
    static func accepted(desired: Set<String>, owned: Set<String>) -> Set<String> {
        desired.intersection(owned)
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
