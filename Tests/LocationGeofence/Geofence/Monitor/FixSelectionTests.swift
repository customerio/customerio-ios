@testable import CioInternalCommon
@testable import CioLocationGeofence
import CoreLocation
import Foundation
import Testing

@Suite("FixSelection")
struct FixSelectionTests {
    private func fix(latitude: Double, ageSeconds: TimeInterval, at timestamp: Date? = nil) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: 74),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            timestamp: timestamp ?? Date(timeIntervalSinceNow: -ageSeconds)
        )
    }

    @Test
    func newest_givenNeitherSource_expectNothing() {
        #expect(FixSelection.newest(cached: nil, delivered: nil) == nil)
    }

    @Test
    func newest_givenOnlyTheOsCache_expectItReportedAsCache() {
        let result = FixSelection.newest(cached: fix(latitude: 31.7, ageSeconds: 5), delivered: nil)

        #expect(result?.fix.coordinate.latitude == 31.7)
        #expect(result?.source == .managerCache)
    }

    @Test
    func newest_givenOnlyADeliveredFix_expectItReportedAsResolver() {
        let result = FixSelection.newest(cached: nil, delivered: fix(latitude: 31.1, ageSeconds: 5))

        #expect(result?.fix.coordinate.latitude == 31.1)
        #expect(result?.source == .resolver)
    }

    @Test
    func newest_givenTheCacheIsNewer_expectTheCache() {
        let result = FixSelection.newest(
            cached: fix(latitude: 31.7, ageSeconds: 5),
            delivered: fix(latitude: 31.1, ageSeconds: 120)
        )

        #expect(result?.fix.coordinate.latitude == 31.7)
        #expect(result?.source == .managerCache)
    }

    @Test
    func newest_givenTheDeliveredFixIsNewer_expectTheDeliveredFix() {
        let result = FixSelection.newest(
            cached: fix(latitude: 31.7, ageSeconds: 120),
            delivered: fix(latitude: 31.1, ageSeconds: 5)
        )

        #expect(result?.fix.coordinate.latitude == 31.1)
        #expect(result?.source == .resolver)
    }

    /// The case the three hand-rolled copies disagreed on. The value is the same either way, but
    /// `fixsrc` is what the field analysis reads, so the tie has to resolve one way everywhere.
    @Test
    func newest_givenEqualTimestamps_expectTheDeliveredFix() {
        let sameMoment = Date(timeIntervalSince1970: 1700000000)
        let result = FixSelection.newest(
            cached: fix(latitude: 31.7, ageSeconds: 0, at: sameMoment),
            delivered: fix(latitude: 31.1, ageSeconds: 0, at: sameMoment)
        )

        #expect(result?.fix.coordinate.latitude == 31.1)
        #expect(result?.source == .resolver)
    }

    /// An unusable coordinate must not win on age: as the freshness baseline it would make a
    /// genuinely newer delivered fix look not-newer.
    @Test
    func usable_givenAnInvalidCoordinate_expectNothingToSelect() {
        let invalid = CLLocation(latitude: 9999, longitude: 9999)

        #expect(FixSelection.usable(invalid) == nil)
        #expect(FixSelection.newest(
            cached: FixSelection.usable(invalid),
            delivered: fix(latitude: 31.1, ageSeconds: 120)
        )?.source == .resolver)
    }
}
