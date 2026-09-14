import CioInternalCommon
import Foundation

/// Disposition of a state observed off `CLMonitor.events`, decided by
/// `GeofenceStorage.recordMonitorEvent(_:forIdentifier:)`.
enum GeofenceMonitorEventOutcome: Equatable, Sendable, CaseIterable {
    /// Genuine state change of a registered transition type — deliver it.
    case deliver
    /// Same state as the baseline — a CLMonitor re-emission (relaunch/unlock/foreground), not a crossing.
    case suppressedNoChange
    /// Genuine state change, but the region wasn't registered for this transition type.
    case suppressedFilteredType
    /// First observation for a condition with no registration record — baseline established, nothing delivered.
    case suppressedNoBaseline
    /// The baseline was written after the caller's evidence (`onlyIfBaselinePredates`) — e.g. a
    /// heal whose fix predates an OS crossing that landed while the heal was queued.
    case suppressedNewerBaseline
    /// An OS event dated at or before the last one processed for this condition: CoreLocation
    /// handing the same event over again (`osEventDate`).
    case suppressedRedelivery
    /// An OS event dated before the condition's current circle was installed: computed against a
    /// circle that no longer exists, so its state says nothing about this one (`osEventDate`).
    case suppressedPredatesRegistration
}
