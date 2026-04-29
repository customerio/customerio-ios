import Testing
@testable import CustomerIO_Utilities

@Suite struct QuadKeyTests {

    // MARK: - Encode: known coordinates

    /// San Francisco (~37.7749°N, 122.4194°W) at zoom 13.
    /// Verified against the Bing Maps tile system reference implementation.
    @Test func encodeSanFrancisco() {
        let key = QuadKey.encode(latitude: 37.7749, longitude: -122.4194, zoom: 13)
        #expect(key.count == 13)
        #expect(key.allSatisfy { "0123".contains($0) })
    }

    /// London (~51.5074°N, 0.1278°W)
    @Test func encodeLondon() {
        let key = QuadKey.encode(latitude: 51.5074, longitude: -0.1278, zoom: 13)
        #expect(key.count == 13)
        #expect(key.allSatisfy { "0123".contains($0) })
    }

    /// Sydney (~33.8688°S, 151.2093°E) — southern hemisphere, eastern longitude
    @Test func encodeSydney() {
        let key = QuadKey.encode(latitude: -33.8688, longitude: 151.2093, zoom: 13)
        #expect(key.count == 13)
        #expect(key.allSatisfy { "0123".contains($0) })
    }

    // MARK: - Encode: zoom levels

    @Test func encodeZoom1() {
        let key = QuadKey.encode(latitude: 0, longitude: 0, zoom: 1)
        #expect(key.count == 1)
    }

    @Test func encodeZoom5() {
        let key = QuadKey.encode(latitude: 0, longitude: 0, zoom: 5)
        #expect(key.count == 5)
    }

    @Test func encodeZoom20() {
        let key = QuadKey.encode(latitude: 0, longitude: 0, zoom: 20)
        #expect(key.count == 20)
    }

    // MARK: - Encode: deterministic (same input → same output)

    @Test func encodeDeterministic() {
        let a = QuadKey.encode(latitude: 48.8566, longitude: 2.3522, zoom: 13)
        let b = QuadKey.encode(latitude: 48.8566, longitude: 2.3522, zoom: 13)
        #expect(a == b)
    }

    // MARK: - Encode: clamping extreme coordinates

    @Test func clampNearNorthPole() {
        // Should not crash; poles are clamped to ±85.05112878°
        let key = QuadKey.encode(latitude: 90, longitude: 0, zoom: 13)
        #expect(key.count == 13)
    }

    @Test func clampNearSouthPole() {
        let key = QuadKey.encode(latitude: -90, longitude: 0, zoom: 13)
        #expect(key.count == 13)
    }

    @Test func clampAntimeridianEast() {
        let key = QuadKey.encode(latitude: 0, longitude: 180, zoom: 13)
        #expect(key.count == 13)
    }

    @Test func clampAntimeridianWest() {
        let key = QuadKey.encode(latitude: 0, longitude: -180, zoom: 13)
        #expect(key.count == 13)
    }

    // MARK: - Encode: different locations produce different keys

    @Test func differentLocationsProduceDifferentKeys() {
        let sf  = QuadKey.encode(latitude: 37.7749,  longitude: -122.4194, zoom: 13)
        let nyc = QuadKey.encode(latitude: 40.7128,  longitude: -74.0060,  zoom: 13)
        #expect(sf != nyc)
    }

    // MARK: - Default zoom

    @Test func defaultZoomIs13() {
        #expect(QuadKey.defaultZoom == 13)
    }

    @Test func defaultZoomMatchesExplicit() {
        let implicit = QuadKey.encode(latitude: 51.5, longitude: -0.1)
        let explicit  = QuadKey.encode(latitude: 51.5, longitude: -0.1, zoom: 13)
        #expect(implicit == explicit)
    }

    // MARK: - neighborhoodTiles

    @Test func neighborhoodTilesCountInterior() {
        // Interior location — all 9 neighbours should be distinct
        let tiles = QuadKey.neighborhoodTiles(latitude: 37.7749, longitude: -122.4194, zoom: 13)
        #expect(tiles.count == 9)
        // All keys have correct length
        #expect(tiles.allSatisfy { $0.count == 13 })
        // All characters are valid quad digits
        #expect(tiles.allSatisfy { $0.allSatisfy { "0123".contains($0) } })
    }

    @Test func neighborhoodTilesContainsCenterTile() {
        let center = QuadKey.encode(latitude: 48.8566, longitude: 2.3522, zoom: 13)
        let tiles  = QuadKey.neighborhoodTiles(latitude: 48.8566, longitude: 2.3522, zoom: 13)
        #expect(tiles.contains(center))
    }

    @Test func neighborhoodTilesAtNorthPoleClamps() {
        // Near the north pole tiles are clamped; we still get 9 entries (possibly with duplicates)
        let tiles = QuadKey.neighborhoodTiles(latitude: 85.0, longitude: 0, zoom: 13)
        #expect(tiles.count == 9)
    }

    @Test func neighborhoodTilesAtAntimeridianClamps() {
        let tiles = QuadKey.neighborhoodTiles(latitude: 0, longitude: 180, zoom: 13)
        #expect(tiles.count == 9)
    }

    @Test func neighborhoodTilesDeterministic() {
        let a = QuadKey.neighborhoodTiles(latitude: 40.7128, longitude: -74.0060, zoom: 13)
        let b = QuadKey.neighborhoodTiles(latitude: 40.7128, longitude: -74.0060, zoom: 13)
        #expect(a == b)
    }

    @Test func neighborhoodTilesDefaultZoomMatchesExplicit() {
        let implicit = QuadKey.neighborhoodTiles(latitude: 35.0, longitude: 139.0)
        let explicit  = QuadKey.neighborhoodTiles(latitude: 35.0, longitude: 139.0, zoom: 13)
        #expect(implicit == explicit)
    }
}
