import CioInternalCommon
import CoreLocation
import Foundation

/// Shared by both monitors and the resolver, so the tie rule and the logged `fixsrc` can't drift.
enum FixSelection {
    /// A tie goes to the delivered fix, so `fixsrc=resolver` means "at least as new as the OS cache".
    static func newest(
        cached: CLLocation?,
        delivered: CLLocation?
    ) -> (fix: CLLocation, source: GeofenceLog.FixSource)? {
        guard let delivered else { return cached.map { ($0, .managerCache) } }
        guard let cached else { return (delivered, .resolver) }
        return cached.timestamp > delivered.timestamp ? (cached, .managerCache) : (delivered, .resolver)
    }

    static func usable(_ fix: CLLocation?) -> CLLocation? {
        fix.flatMap { CLLocationCoordinate2DIsValid($0.coordinate) ? $0 : nil }
    }
}

/// Which fix both monitors act on, as a protocol default so neither hand-rolls its own.
@MainActor
protocol GeofenceFixSelecting: AnyObject {
    var osCachedFix: CLLocation? { get }
    var movementFixResolver: MovementFixResolver { get }
    /// Don't implement `bestKnownFixDetail()` in a conformer: `bestKnownFix()` dispatches statically
    /// and wouldn't see it.
    var logger: Logger { get }
    var dateUtil: DateUtil { get }
}

extension GeofenceFixSelecting {
    /// The OS cache can freeze in a long-suspended process, so a fresher resolver fix must win.
    func bestKnownFix() -> CLLocation? {
        bestKnownFixDetail()?.fix
    }

    func bestKnownFixDetail() -> (fix: CLLocation, source: GeofenceLog.FixSource)? {
        let selected = FixSelection.newest(cached: FixSelection.usable(osCachedFix), delivered: movementFixResolver.latestFix)
        // Every cache read is an input and is logged, repeated or not.
        logger.geofenceLocationFix(selected?.fix, source: selected?.source ?? .none, now: dateUtil.now)
        return selected
    }
}
