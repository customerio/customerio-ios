import CioInternalCommon
import Foundation

/// Split from the resolver's core for the file cap.
@MainActor
extension PolygonMembershipResolver {
    /// The pass for polygons a refresh has just registered.
    ///
    /// Forces a fresh fix so this and the movement pass the same refresh starts judge from the same
    /// one. A cached fix can be up to `movementFixMaxAge` old, hundreds of metres at speed, and
    /// deciding from it here could deliver an enter the movement pass then reverses.
    ///
    /// Falls back to the cached fix when the request fails, because enter-when-inside is still
    /// owed. That verdict is older evidence than any later fresh one, so the ordering guard lets a
    /// fresh verdict correct it.
    func evaluateNewlyRegistered(
        geofenceIds: [String],
        isStillCurrent: (@Sendable () -> Bool)? = nil
    ) async {
        let decided = await evaluateMembership(
            geofenceIds: geofenceIds, reason: .newPolygon,
            requiresFreshFix: true, isStillCurrent: isStillCurrent
        )
        guard !decided else { return }
        await evaluateMembership(
            geofenceIds: geofenceIds, reason: .newPolygonForcedRequestFailed,
            isStillCurrent: isStillCurrent
        )
    }
}
