import CioInternalCommon
import Foundation

/// The pass for polygons a refresh has just registered, split from the resolver's core so both stay
/// under the file cap.
@MainActor
extension PolygonMembershipResolver {
    /// The pass for polygons a refresh has just registered.
    ///
    /// Forces a fresh fix so this and the movement pass the same refresh starts decide from the
    /// same one. Deciding here from a cached fix while the movement pass forces a fresh one let a
    /// single refresh deliver an enter and then its own correcting exit: the cached fix is accepted
    /// up to `movementFixMaxAge` old, which at speed is the several hundred metres the movement
    /// pass forces a fresh fix precisely to avoid.
    ///
    /// The cached fix stays as the fallback for a failed request, because enter-when-inside is owed
    /// for a polygon the device is standing in and the movement pass will have decided nothing
    /// either. It cannot resurrect the contradiction: a verdict it writes is older evidence than
    /// any later fresh one, so the ordering guard lets the fresh verdict correct it.
    func evaluateNewlyRegistered(
        geofenceIds: [String],
        isStillCurrent: (@Sendable () -> Bool)? = nil
    ) async {
        let decided = await evaluateMembership(
            geofenceIds: geofenceIds, reason: "new polygon",
            requiresFreshFix: true, isStillCurrent: isStillCurrent
        )
        guard !decided else { return }
        await evaluateMembership(
            geofenceIds: geofenceIds, reason: "new polygon, forced request failed",
            isStillCurrent: isStillCurrent
        )
    }
}
