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
        {"config":{"ios":{"max_business_geofence":0}},"geofences":[]}
        """
        let response = try decode(json)
        #expect(response.toDomainConfig()?.maxBusinessGeofences == 0)
    }

    @Test
    func toDomainConfig_givenIosMaxBusinessGeofencesOutOfRange_expectFallback() throws {
        let json = """
        {"config":{"ios":{"max_business_geofence":25}},"geofences":[]}
        """
        let response = try decode(json)
        #expect(response.toDomainConfig()?.maxBusinessGeofences == GeofenceConstants.maxMonitoredGeofences)
    }

    @Test
    func toDomainConfig_givenIosMaxBusinessGeofencesAtUpperBound_expectPreserved() throws {
        // 19 is the inclusive upper bound (movement trigger consumes the 20th OS slot).
        let json = """
        {"config":{"ios":{"max_business_geofence":19}},"geofences":[]}
        """
        let response = try decode(json)
        #expect(response.toDomainConfig()?.maxBusinessGeofences == 19)
    }

    @Test
    func toDomainConfig_givenIosMaxBusinessGeofencesNegative_expectFallback() throws {
        let json = """
        {"config":{"ios":{"max_business_geofence":-1}},"geofences":[]}
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
    func toDomainRegions_givenNumericId_expectDecodedAsString() throws {
        // The backend sends `id` as a JSON number; it must decode and normalize to a String.
        let json = """
        {"geofences":[{"id":4,"latitude":1,"longitude":2,"radius":100}]}
        """
        let response = try decode(json)
        #expect(response.toDomainRegions().first?.id == "4")
    }

    @Test
    func toDomainRegions_givenStringId_expectDecodedUnchanged() throws {
        let json = """
        {"geofences":[{"id":"g1","latitude":1,"longitude":2,"radius":100}]}
        """
        let response = try decode(json)
        #expect(response.toDomainRegions().first?.id == "g1")
    }

    @Test
    func toDomainRegions_givenMinimalRegion_expectDefaults() throws {
        let json = """
        {"geofences":[{"id":"g1","latitude":1,"longitude":2,"radius":100}]}
        """
        let response = try decode(json)
        let region = response.toDomainRegions().first

        #expect(region?.id == "g1")
        #expect(region?.name == nil)
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
    func toDomainRegions_givenNonPositiveRadius_expectDropped() throws {
        let json = """
        {"geofences":[
          {"id":"g0","latitude":1,"longitude":2,"radius":0},
          {"id":"g-neg","latitude":1,"longitude":2,"radius":-50}
        ]}
        """
        let response = try decode(json)
        #expect(response.toDomainRegions().isEmpty)
    }

    @Test
    func toDomainRegions_givenOutOfRangeCoordinates_expectDropped() throws {
        let json = """
        {"geofences":[
          {"id":"lat-high","latitude":90.1,"longitude":2,"radius":100},
          {"id":"lat-low","latitude":-90.1,"longitude":2,"radius":100},
          {"id":"lon-high","latitude":1,"longitude":180.1,"radius":100},
          {"id":"lon-low","latitude":1,"longitude":-180.1,"radius":100}
        ]}
        """
        let response = try decode(json)
        #expect(response.toDomainRegions().isEmpty)
    }

    @Test
    func toDomainRegions_givenMixedValidAndInvalidRegions_expectValidKeptAndInvalidReported() throws {
        // One bad server region must cost itself, not the rest of the sync.
        let json = """
        {"geofences":[
          {"id":"good","latitude":1,"longitude":2,"radius":100},
          {"id":"bad","latitude":91,"longitude":2,"radius":100}
        ]}
        """
        let response = try decode(json)
        var droppedIds: [String] = []
        let regions = response.toDomainRegions(onInvalidRegion: { id, _ in droppedIds.append(id) })

        #expect(regions.map(\.id) == ["good"])
        #expect(droppedIds == ["bad"])
    }

    @Test
    func toDomainRegions_givenBoundaryCoordinates_expectKept() throws {
        // The exact poles/antimeridian are valid registerable coordinates.
        let json = """
        {"geofences":[{"id":"edge","latitude":90,"longitude":-180,"radius":100}]}
        """
        let response = try decode(json)
        #expect(response.toDomainRegions().first?.id == "edge")
    }

    @Test
    func toDomainRegions_givenLastUpdatedMillis_expectConvertedToSeconds() throws {
        // Wire value is epoch milliseconds; the domain `Date` is seconds.
        let json = """
        {"geofences":[{"id":"g1","latitude":1,"longitude":2,"radius":100,"last_updated":1700000000000}]}
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

    @Test
    func toDomainRegions_givenGeosetIds_expectCarriedToDomain() throws {
        let json = """
        {"geofences":[{"id":"g1","latitude":1,"longitude":2,"radius":100,"geoset_ids":["set_y","set_z"]}]}
        """
        let response = try decode(json)
        #expect(response.toDomainRegions().first?.geosetIds == ["set_y", "set_z"])
    }

    @Test
    func toDomainRegions_givenNumericGeosetIds_expectNormalizedToStrings() throws {
        // The server contract: `geoset_ids` is `[]int64`, so ids arrive as JSON numbers. This is the
        // common case and must always decode; we normalize to String for downstream flexibility.
        let json = """
        {"geofences":[{"id":"g1","latitude":1,"longitude":2,"radius":100,"geoset_ids":[1,3,7]}]}
        """
        let response = try decode(json)
        #expect(response.toDomainRegions().first?.geosetIds == ["1", "3", "7"])
    }

    @Test
    func toDomainRegions_givenLargeInt64GeosetId_expectNoPrecisionLoss() throws {
        // int64 exceeds JSON/Double safe-integer range; decoding via Int64 (not Double) keeps large
        // ids exact. 9007199254740993 (2^53 + 1) would collapse to ...992 through a Double.
        let json = """
        {"geofences":[{"id":"g1","latitude":1,"longitude":2,"radius":100,"geoset_ids":[9007199254740993]}]}
        """
        let response = try decode(json)
        #expect(response.toDomainRegions().first?.geosetIds == ["9007199254740993"])
    }

    @Test
    func toDomainRegions_givenMissingGeosetIds_expectEmpty() throws {
        // Backend rolls `geoset_ids` out gradually; absent means no geoset membership.
        let json = """
        {"geofences":[{"id":"g1","latitude":1,"longitude":2,"radius":100}]}
        """
        let response = try decode(json)
        #expect(response.toDomainRegions().first?.geosetIds == [])
    }

    @Test
    func toDomainRegions_givenNullGeosetIds_expectEmpty() throws {
        // Explicit JSON null must decode to no membership, not throw and fail the whole response.
        let json = """
        {"geofences":[{"id":"g1","latitude":1,"longitude":2,"radius":100,"geoset_ids":null}]}
        """
        let response = try decode(json)
        #expect(response.toDomainRegions().first?.geosetIds == [])
    }

    // MARK: - Metadata (server field `metadata`, type-preserved)

    @Test
    func toDomainRegions_givenScalarMetadata_expectTypesPreserved() throws {
        let json = """
        {"geofences":[{"id":"g1","latitude":1,"longitude":2,"radius":100,
          "metadata":{"category":"office","priority":3,"score":1.5,"vip":true}}]}
        """
        let metadata = try #require(try decode(json).toDomainRegions().first?.metadata)
        #expect(metadata["category"] == .string("office"))
        #expect(metadata["priority"] == .int(3))
        #expect(metadata["score"] == .double(1.5))
        #expect(metadata["vip"] == .bool(true))
    }

    @Test
    func toDomainRegions_givenMissingMetadata_expectEmpty() throws {
        let json = """
        {"geofences":[{"id":"g1","latitude":1,"longitude":2,"radius":100}]}
        """
        #expect(try decode(json).toDomainRegions().first?.metadata == [:])
    }

    @Test
    func toDomainRegions_givenEmptyMetadata_expectEmpty() throws {
        let json = """
        {"geofences":[{"id":"g1","latitude":1,"longitude":2,"radius":100,"metadata":{}}]}
        """
        #expect(try decode(json).toDomainRegions().first?.metadata == [:])
    }

    @Test
    func toDomainRegions_givenNullOrNonScalarMetadataValues_expectDroppedNotFailed() throws {
        // A null, nested object, or array value must drop that single entry, not fail the region.
        let json = """
        {"geofences":[{"id":"g1","latitude":1,"longitude":2,"radius":100,
          "metadata":{"good":"ok","bad":null,"nested":{"a":1},"list":[1,2]}}]}
        """
        #expect(try decode(json).toDomainRegions().first?.metadata == ["good": .string("ok")])
    }

    @Test
    func toDomainRegions_givenMalformedMetadataType_expectEmptyMetadataAndRegionStillParses() throws {
        // `metadata` sent as a non-object (here a string) must not fail the region/response decode —
        // it degrades to empty metadata while every other field parses normally.
        let json = """
        {"geofences":[{"id":"g1","latitude":1.5,"longitude":2.5,"radius":100,"metadata":"oops"}]}
        """
        let region = try #require(try decode(json).toDomainRegions().first)
        #expect(region.id == "g1")
        #expect(region.latitude == 1.5)
        #expect(region.metadata == [:])
    }

    @Test
    func toDomainRegions_givenMetadataBeyondCountCap_expectCappedByKeyOrder() throws {
        let entries = (0 ..< (GeofenceConstants.maxMetadataCount + 5))
            .map { "\"k\(String(format: "%03d", $0))\":\"v\($0)\"" }
            .joined(separator: ",")
        let json = """
        {"geofences":[{"id":"g1","latitude":1,"longitude":2,"radius":100,"metadata":{\(entries)}}]}
        """
        let metadata = try #require(try decode(json).toDomainRegions().first?.metadata)
        #expect(metadata.count == GeofenceConstants.maxMetadataCount)
        // Kept set is deterministic (sorted by key): k000 in, the overflow tail out.
        #expect(metadata["k000"] == .string("v0"))
        #expect(metadata["k\(String(format: "%03d", GeofenceConstants.maxMetadataCount + 2))"] == nil)
    }

    @Test
    func toDomainRegions_givenTotalPayloadBeyondByteCap_expectStoppedAtByteBudget() throws {
        // Umbrella guard: values are bounded by the total byte budget, independent of the count cap.
        // Each value is ~1/4 of the budget, so 8 of them overrun it and only a few are kept.
        let bigValue = String(repeating: "a", count: GeofenceConstants.maxMetadataPayloadBytes / 4)
        let generated = 8
        let entries = (0 ..< generated)
            .map { "\"k\($0)\":\"\(bigValue)\"" }
            .joined(separator: ",")
        let json = """
        {"geofences":[{"id":"g1","latitude":1,"longitude":2,"radius":100,"metadata":{\(entries)}}]}
        """
        let metadata = try #require(try decode(json).toDomainRegions().first?.metadata)
        let totalBytes = metadata.reduce(0) { sum, entry in
            guard case .string(let value) = entry.value else { return sum }
            return sum + entry.key.utf8.count + value.utf8.count
        }
        #expect(totalBytes <= GeofenceConstants.maxMetadataPayloadBytes)
        #expect(metadata.count < generated) // byte budget dropped some
    }

    // MARK: - One bad region must not cost the response

    @Test
    func decode_givenOneWrongTypedRegion_expectOthersSurvive() throws {
        let json = """
        {"geofences":[
          {"id":"good","latitude":1,"longitude":2,"radius":100},
          {"id":"bad","latitude":1,"longitude":2,"radius":"not-a-number"},
          {"id":"alsoGood","latitude":3,"longitude":4,"radius":200}
        ]}
        """
        let response = try decode(json)
        #expect(response.receivedRegionCount == 3)
        #expect(response.toDomainRegions().map(\.id) == ["good", "alsoGood"])
    }

    /// Distinguishes "the server sent none" from "none of them decoded" — the caller wipes the
    /// cache on the first and must not on the second.
    @Test
    func decode_givenEveryRegionWrongTyped_expectCountPreservedAndListEmpty() throws {
        let json = """
        {"geofences":[
          {"id":"a","latitude":1,"longitude":2,"radius":"nope"},
          {"id":"b","latitude":"nope","longitude":2,"radius":100}
        ]}
        """
        let response = try decode(json)
        #expect(response.receivedRegionCount == 2)
        #expect(response.geofences.isEmpty)
    }

    @Test
    func decode_givenGenuinelyEmptyList_expectZeroReceived() throws {
        let response = try decode("{\"geofences\":[]}")
        #expect(response.receivedRegionCount == 0)
    }

    @Test
    func toDomainRegions_givenUnknownShape_expectShapeReasonReported() throws {
        let json = """
        {"geofences":[{"id":"weird","shape":"hexagon","latitude":1,"longitude":2,"radius":100}]}
        """
        var reasons: [String: GeofenceRegionDropReason] = [:]
        let regions = try decode(json).toDomainRegions(onInvalidRegion: { reasons[$0] = $1 })
        #expect(regions.isEmpty)
        #expect(reasons["weird"] == .unknownShape)
    }

    @Test
    func toDomainRegions_givenUnusableCircle_expectCircleReasonReported() throws {
        let json = """
        {"geofences":[{"id":"c","latitude":91,"longitude":2,"radius":100}]}
        """
        var reasons: [String: GeofenceRegionDropReason] = [:]
        _ = try decode(json).toDomainRegions(onInvalidRegion: { reasons[$0] = $1 })
        #expect(reasons["c"] == .unusableCircle)
    }
}
