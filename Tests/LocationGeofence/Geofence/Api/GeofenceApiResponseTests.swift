@testable import CioInternalCommon
@testable import CioLocationGeofence
import Foundation
import Testing

@Suite("GeofenceApiResponse")
struct GeofenceApiResponseTests {
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    private func decode(_ json: String) throws -> GeofenceApiResponse {
        try decoder.decode(GeofenceApiResponse.self, from: Data(json.utf8))
    }

    // MARK: - Config sanitization

    @Test
    func toDomainConfig_givenMissingConfigBlock_expectNil() throws {
        let response = try decode("{\"geofences\":[]}")
        #expect(response.toDomainConfig() == nil)
    }

    @Test
    func toDomainConfig_givenAllFieldsMissing_expectFallbackValues() throws {
        let response = try decode("{\"config\":{},\"geofences\":[]}")
        let config = response.toDomainConfig()
        #expect(config == .fallback)
    }

    @Test
    func toDomainConfig_givenNonPositiveNumerics_expectFallbackPerField() throws {
        let json = """
        {
          "config": {
            "local_refresh_trigger_radius": 0,
            "remote_fetch_refresh_trigger_radius": -50,
            "remote_fetch_refresh_expiry_time": 0,
            "duplicate_events_expiry_time": -1
          },
          "geofences": []
        }
        """
        let response = try decode(json)
        let config = response.toDomainConfig()
        #expect(config?.localRefreshTriggerRadius == GeofenceConstants.movementTriggerRadius)
        #expect(config?.remoteFetchRefreshTriggerRadius == GeofenceConstants.serverFetchDistance)
        #expect(config?.remoteFetchRefreshExpiry == GeofenceConstants.staleSyncInterval)
        #expect(config?.duplicateEventsExpiry == GeofenceConstants.eventCooldownInterval)
    }

    @Test
    func toDomainConfig_givenIosMaxBusinessGeofencesZero_expectKillSwitchPreserved() throws {
        let json = """
        {"config":{"ios":{"max_business_geofences":0}},"geofences":[]}
        """
        let response = try decode(json)
        #expect(response.toDomainConfig()?.maxBusinessGeofences == 0)
    }

    @Test
    func toDomainConfig_givenIosMaxBusinessGeofencesOutOfRange_expectFallback() throws {
        let json = """
        {"config":{"ios":{"max_business_geofences":25}},"geofences":[]}
        """
        let response = try decode(json)
        #expect(response.toDomainConfig()?.maxBusinessGeofences == GeofenceConstants.maxMonitoredGeofences)
    }

    @Test
    func toDomainConfig_givenIosMaxBusinessGeofencesAtUpperBound_expectPreserved() throws {
        // 19 is the inclusive upper bound (movement trigger consumes the 20th OS slot).
        let json = """
        {"config":{"ios":{"max_business_geofences":19}},"geofences":[]}
        """
        let response = try decode(json)
        #expect(response.toDomainConfig()?.maxBusinessGeofences == 19)
    }

    @Test
    func toDomainConfig_givenIosMaxBusinessGeofencesNegative_expectFallback() throws {
        let json = """
        {"config":{"ios":{"max_business_geofences":-1}},"geofences":[]}
        """
        let response = try decode(json)
        #expect(response.toDomainConfig()?.maxBusinessGeofences == GeofenceConstants.maxMonitoredGeofences)
    }

    @Test
    func toDomainConfig_givenMillisecondExpiryValues_expectConvertedToSeconds() throws {
        let json = """
        {
          "config": {
            "remote_fetch_refresh_expiry_time": 7200000,
            "duplicate_events_expiry_time": 60000
          },
          "geofences": []
        }
        """
        let response = try decode(json)
        let config = response.toDomainConfig()
        #expect(config?.remoteFetchRefreshExpiry == 7200) // 2 hours in seconds
        #expect(config?.duplicateEventsExpiry == 60)
    }

    @Test
    func toDomainConfig_givenLocalRefreshRadiusBelowMin_expectClampedToMin() throws {
        let response = try decode("{\"config\":{\"local_refresh_trigger_radius\":10},\"geofences\":[]}")
        #expect(response.toDomainConfig()?.localRefreshTriggerRadius == GeofenceConstants.minLocalRefreshRadius)
    }

    @Test
    func toDomainConfig_givenLocalRefreshRadiusAboveMax_expectClampedToMax() throws {
        let response = try decode("{\"config\":{\"local_refresh_trigger_radius\":99999},\"geofences\":[]}")
        #expect(response.toDomainConfig()?.localRefreshTriggerRadius == GeofenceConstants.maxLocalRefreshRadius)
    }

    @Test
    func toDomainConfig_givenExpiriesOutOfRange_expectClamped() throws {
        // 1s (below the 1-min min) and 48h (above the 24h max), both in ms.
        let json = """
        {"config":{"remote_fetch_refresh_expiry_time":1000,"duplicate_events_expiry_time":172800000},"geofences":[]}
        """
        let response = try decode(json)
        let config = response.toDomainConfig()
        #expect(config?.remoteFetchRefreshExpiry == GeofenceConstants.minRemoteFetchRefreshExpiry)
        #expect(config?.duplicateEventsExpiry == GeofenceConstants.maxDuplicateEventsExpiry)
    }

    @Test
    func toDomainConfig_givenMaxMonitoringDistanceAbsent_expectDefaultCap() throws {
        // The server omits the field today — apply the default cap, not "unlimited".
        let response = try decode("{\"config\":{\"local_refresh_trigger_radius\":3000},\"geofences\":[]}")
        #expect(response.toDomainConfig()?.maxMonitoringDistance == GeofenceConstants.defaultMaxMonitoringDistance)
    }

    @Test
    func toDomainConfig_givenMaxMonitoringDistanceZero_expectNoCap() throws {
        // An explicit 0 is the server's way to turn the cap off.
        let json = """
        {"config":{"local_refresh_trigger_radius":3000,"max_monitoring_distance":0},"geofences":[]}
        """
        let response = try decode(json)
        #expect(response.toDomainConfig()?.maxMonitoringDistance == GeofenceConstants.noMonitoringDistanceCap)
    }

    @Test
    func toDomainConfig_givenMaxMonitoringDistanceBelowTriggerRadius_expectDefaultCap() throws {
        // A cap below the trigger radius would create a dead-zone → falls back to the default cap.
        let json = """
        {"config":{"local_refresh_trigger_radius":3000,"max_monitoring_distance":1000},"geofences":[]}
        """
        let response = try decode(json)
        #expect(response.toDomainConfig()?.maxMonitoringDistance == GeofenceConstants.defaultMaxMonitoringDistance)
    }

    @Test
    func toDomainConfig_givenMaxMonitoringDistanceAboveTriggerRadius_expectPreserved() throws {
        let json = """
        {"config":{"local_refresh_trigger_radius":3000,"max_monitoring_distance":10000},"geofences":[]}
        """
        let response = try decode(json)
        #expect(response.toDomainConfig()?.maxMonitoringDistance == 10000)
    }

    // MARK: - Region mapping

    @Test
    func toDomainRegions_givenMinimalRegion_expectDefaults() throws {
        let json = """
        {"geofences":[{"id":"g1","latitude":1,"longitude":2,"radius":100}]}
        """
        let response = try decode(json)
        let region = response.toDomainRegions().first

        #expect(region?.id == "g1")
        #expect(region?.name == "")
        #expect(region?.transitionTypes == [.enter, .exit])
        #expect(region?.lastUpdated == Date(timeIntervalSince1970: 0))
    }

    @Test
    func toDomainRegions_givenEmptyTransitionTypes_expectDefaults() throws {
        let json = """
        {"geofences":[{"id":"g1","latitude":1,"longitude":2,"radius":100,"transition_types":[]}]}
        """
        let response = try decode(json)
        #expect(response.toDomainRegions().first?.transitionTypes == [.enter, .exit])
    }

    @Test
    func toDomainRegions_givenAllUnknownTransitionTypes_expectDefaults() throws {
        let json = """
        {"geofences":[{"id":"g1","latitude":1,"longitude":2,"radius":100,"transition_types":["dwell","loiter"]}]}
        """
        let response = try decode(json)
        #expect(response.toDomainRegions().first?.transitionTypes == [.enter, .exit])
    }

    @Test
    func toDomainRegions_givenMixedValidAndUnknownTransitionTypes_expectValidSubset() throws {
        let json = """
        {"geofences":[{"id":"g1","latitude":1,"longitude":2,"radius":100,"transition_types":["enter","dwell"]}]}
        """
        let response = try decode(json)
        #expect(response.toDomainRegions().first?.transitionTypes == [.enter])
    }

    @Test
    func toDomainRegions_givenLastUpdatedSeconds_expectDate() throws {
        let json = """
        {"geofences":[{"id":"g1","latitude":1,"longitude":2,"radius":100,"last_updated":1700000000}]}
        """
        let response = try decode(json)
        #expect(response.toDomainRegions().first?.lastUpdated == Date(timeIntervalSince1970: 1700000000))
    }

    @Test
    func toDomainRegions_givenCaseInsensitiveTransitionTypes_expectParsed() throws {
        let json = """
        {"geofences":[{"id":"g1","latitude":1,"longitude":2,"radius":100,"transition_types":["ENTER","Exit"]}]}
        """
        let response = try decode(json)
        #expect(response.toDomainRegions().first?.transitionTypes == [.enter, .exit])
    }
}
