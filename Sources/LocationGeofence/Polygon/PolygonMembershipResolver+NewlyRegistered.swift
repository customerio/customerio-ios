import CioInternalCommon
import Foundation

@MainActor
extension PolygonMembershipResolver {
    /// Forces a fresh fix so this and the refresh's movement pass judge from the same one. Falls back
    /// to the cached fix on failure: enter-when-inside is still owed.
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
