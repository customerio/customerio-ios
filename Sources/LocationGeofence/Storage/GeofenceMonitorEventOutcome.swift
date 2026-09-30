import CioInternalCommon
import Foundation

/// Disposition of a `CLMonitor.events` state, decided by `GeofenceStorage.recordMonitorEvent`.
enum GeofenceMonitorEventOutcome: Equatable, Sendable, CaseIterable {
    case deliver
    /// A CLMonitor re-emission (relaunch/unlock/foreground), not a crossing.
    case suppressedNoChange
    case suppressedFilteredType
    /// The baseline is established; nothing delivered.
    case suppressedNoBaseline
    /// The baseline postdates the caller's evidence (`onlyIfBaselinePredates`).
    case suppressedNewerBaseline
    case suppressedRedelivery
    case suppressedPredatesRegistration
}
