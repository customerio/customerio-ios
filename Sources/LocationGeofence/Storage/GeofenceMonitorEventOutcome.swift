import CioInternalCommon
import Foundation

/// Disposition of a state observed off `CLMonitor.events`, decided by
/// `GeofenceStorage.recordMonitorEvent(_:forIdentifier:)`.
enum GeofenceMonitorEventOutcome: Equatable, Sendable, CaseIterable {
    /// Genuine state change of a registered transition type.
    case deliver
    /// Same state as the baseline: a CLMonitor re-emission (relaunch/unlock/foreground), not a crossing.
    case suppressedNoChange
    /// Genuine state change, but the region wasn't registered for this transition type.
    case suppressedFilteredType
    /// No registration record: the baseline is established and nothing delivered.
    case suppressedNoBaseline
    /// The baseline was written after the caller's evidence (`onlyIfBaselinePredates`), e.g. a heal
    /// whose fix predates an OS crossing that landed while it was queued.
    case suppressedNewerBaseline
    /// An OS event dated at or before the last one processed for this condition: a re-delivery.
    case suppressedRedelivery
    /// An OS event dated before the current circle was installed, so it describes a replaced circle.
    case suppressedPredatesRegistration
}
