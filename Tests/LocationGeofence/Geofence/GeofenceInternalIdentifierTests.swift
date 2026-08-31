@testable import CioLocationGeofence
import Foundation
import Testing

@Suite("GeofenceInternalIdentifier")
struct GeofenceInternalIdentifierTests {
    @Test
    func tripwire_expectRoundTripToItsGeofenceId() {
        let identifier = GeofenceInternalIdentifier.tripwire(for: "1234")
        #expect(GeofenceInternalIdentifier.geofenceId(forTripwire: identifier) == "1234")
    }

    /// Customer geofence ids are server-assigned int64s, so they can never carry the prefix — but
    /// misreading one as a tripwire would route a real crossing to membership re-evaluation and
    /// drop the customer's event, so it is pinned.
    @Test
    func geofenceIdForTripwire_givenCustomerGeofenceId_expectNil() {
        #expect(GeofenceInternalIdentifier.geofenceId(forTripwire: "1234") == nil)
        #expect(GeofenceInternalIdentifier.geofenceId(forTripwire: GeofenceConstants.movementTriggerIdentifier) == nil)
    }

    /// The monitors branch on this to decide three things for a region: that no fix means "assume
    /// the device is inside" (internal regions are planted ON the device), that the contradiction
    /// gate must not vet its events, and that its EXIT gets a freshened fix before dispatch.
    @Test
    func isInternal_expectMovementTriggerAndTripwiresOnly() {
        #expect(GeofenceInternalIdentifier.isInternal(GeofenceConstants.movementTriggerIdentifier))
        #expect(GeofenceInternalIdentifier.isInternal(GeofenceInternalIdentifier.tripwire(for: "1")))
        #expect(!GeofenceInternalIdentifier.isInternal("1"))
        #expect(!GeofenceInternalIdentifier.isInternal(""))
    }
}
