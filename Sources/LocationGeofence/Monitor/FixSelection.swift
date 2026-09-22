import CioInternalCommon
import CoreLocation
import Foundation

/// Picks between the OS's cached fix and the freshest one `MovementFixResolver` has delivered.
///
/// One rule with three readers — both monitors' `bestKnownFixDetail()` and the resolver's own
/// request baseline — which previously hand-rolled it and had already drifted: the monitors gave
/// an equal timestamp to the cache, the resolver to its own fix. Same value either way, but a
/// different `fixsrc` in the diagnostics that the field analysis reads.
enum FixSelection {
    /// The newer of the two, and which one it was. A tie goes to the delivered fix: equal
    /// timestamps mean the cache has caught up to it, and the delivered one is the fix whose
    /// provenance is known rather than whatever the OS last happened to hold.
    ///
    /// So `fixsrc=resolver` in a log reads as "at least as new as the OS cache", not "newer than
    /// it" — worth knowing before inferring provenance from a drive trace.
    static func newest(
        cached: CLLocation?,
        delivered: CLLocation?
    ) -> (fix: CLLocation, source: GeofenceLog.FixSource)? {
        guard let delivered else { return cached.map { ($0, .managerCache) } }
        guard let cached else { return (delivered, .resolver) }
        return cached.timestamp > delivered.timestamp ? (cached, .managerCache) : (delivered, .resolver)
    }

    /// Drops a fix the OS reports at an unusable coordinate, so a caller cannot select one.
    static func usable(_ fix: CLLocation?) -> CLLocation? {
        fix.flatMap { CLLocationCoordinate2DIsValid($0.coordinate) ? $0 : nil }
    }
}

/// The one implementation of "which fix do we act on", shared by both monitors.
///
/// A protocol default rather than a helper each monitor calls: with a helper, a hand-rolled copy
/// back inside either `bestKnownFixDetail()` is a silent drift, and neither monitor can be built
/// in a unit test, so nothing would fail. Here, un-extracting means ADDING a shadowing method,
/// which a reviewer sees.
@MainActor
protocol GeofenceFixSelecting: AnyObject {
    /// The OS's own cached fix, from whichever manager this monitor owns.
    var osCachedFix: CLLocation? { get }
    var movementFixResolver: MovementFixResolver { get }
    /// The selection is logged from the default below, so it is logged identically for both
    /// monitors. Requirements rather than a shadowing override: a concrete `bestKnownFixDetail()`
    /// would not be seen by `bestKnownFix()`, which dispatches statically inside this extension.
    var logger: Logger { get }
    var dateUtil: DateUtil { get }
}

extension GeofenceFixSelecting {
    /// Newest usable fix across the OS cache and the resolver's requested fixes. The OS cache can
    /// freeze at process start on a long-suspended process, so a fresher resolver fix must win
    /// wherever cached position is read.
    func bestKnownFix() -> CLLocation? {
        bestKnownFixDetail()?.fix
    }

    /// The same choice, reporting which source won.
    ///
    /// Worth carrying into diagnostics: a resolver fix was requested and delivered, while the OS
    /// cache is whatever the system last happened to have — and on a long-suspended process that
    /// can be hours old. Both produce a coordinate; only one of them means anything.
    func bestKnownFixDetail() -> (fix: CLLocation, source: GeofenceLog.FixSource)? {
        let selected = FixSelection.newest(cached: FixSelection.usable(osCachedFix), delivered: movementFixResolver.latestFix)
        // Every cache read is an input and is logged, repeated or not.
        logger.geofenceLocationFix(selected?.fix, source: selected?.source ?? .none, now: dateUtil.now)
        return selected
    }
}
