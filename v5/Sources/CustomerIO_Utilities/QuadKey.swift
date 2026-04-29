import Foundation

/// Encodes geographic coordinates as Bing Maps QuadKey strings.
///
/// A QuadKey is a string of digits (0–3) representing a specific tile at a
/// given zoom level in a quadtree subdivision of the map. Zoom level 13
/// produces tiles approximately 4.9 km × 4.9 km near the equator, making it
/// a good granularity for location-based grouping.
///
/// Reference: https://learn.microsoft.com/en-us/bingmaps/articles/bing-maps-tile-system
public enum QuadKey {

    /// Default zoom level used throughout the SDK (~4.9 km tiles).
    public static let defaultZoom: Int = 13

    /// Encode a latitude/longitude pair to a QuadKey string.
    ///
    /// - Parameters:
    ///   - latitude:  WGS-84 latitude in degrees (clamped to ±85.05112878°).
    ///   - longitude: WGS-84 longitude in degrees (clamped to ±180°).
    ///   - zoom:      Tile zoom level (1–23). Default: ``defaultZoom``.
    /// - Returns: A QuadKey string of `zoom` characters, each in `"0123"`.
    public static func encode(
        latitude: Double,
        longitude: Double,
        zoom: Int = defaultZoom
    ) -> String {
        let lat = min(max(latitude, -85.05112878), 85.05112878)
        let lon = min(max(longitude, -180.0), 180.0)

        let sinLat = sin(lat * .pi / 180.0)
        let size = Double(mapSize(zoom))
        let pixelX = Int((lon + 180.0) / 360.0 * size)
        let pixelY = Int(
            (0.5 - log((1.0 + sinLat) / (1.0 - sinLat)) / (4.0 * .pi)) * size
        )

        let tileX = pixelX / 256
        let tileY = pixelY / 256
        return encodeTile(tileX: tileX, tileY: tileY, zoom: zoom)
    }

    /// Returns the QuadKey strings for the 3×3 Moore neighbourhood of tiles centred
    /// on the tile containing the given coordinate.
    ///
    /// Produces 9 QuadKeys (the centre tile plus its 8 immediate neighbours), covering
    /// approximately a 15 × 15 km area at zoom 13. Used for geofence candidate selection.
    /// Tiles at map edges are clamped, so fewer than 9 distinct values may be returned
    /// near the poles or antimeridian.
    public static func neighborhoodTiles(
        latitude: Double,
        longitude: Double,
        zoom: Int = defaultZoom
    ) -> [String] {
        let lat = min(max(latitude, -85.05112878), 85.05112878)
        let lon = min(max(longitude, -180.0), 180.0)

        let sinLat = sin(lat * .pi / 180.0)
        let size = Double(mapSize(zoom))
        let pixelX = Int((lon + 180.0) / 360.0 * size)
        let pixelY = Int(
            (0.5 - log((1.0 + sinLat) / (1.0 - sinLat)) / (4.0 * .pi)) * size
        )

        let centerX = pixelX / 256
        let centerY = pixelY / 256
        let maxTile = (1 << zoom) - 1

        var tiles: [String] = []
        for dx in -1...1 {
            for dy in -1...1 {
                let nx = min(max(centerX + dx, 0), maxTile)
                let ny = min(max(centerY + dy, 0), maxTile)
                tiles.append(encodeTile(tileX: nx, tileY: ny, zoom: zoom))
            }
        }
        return tiles
    }

    // MARK: - Private helpers

    private static func encodeTile(tileX: Int, tileY: Int, zoom: Int) -> String {
        var key = ""
        for level in stride(from: zoom, through: 1, by: -1) {
            var digit = 0
            let mask = 1 << (level - 1)
            if (tileX & mask) != 0 { digit |= 1 }
            if (tileY & mask) != 0 { digit |= 2 }
            key.append(Character(UnicodeScalar(48 + digit)!))  // "0" + digit
        }
        return key
    }

    private static func mapSize(_ zoom: Int) -> Int {
        256 << zoom
    }
}
