// Cross-SDK polygon geometry fixtures. Source of truth: the polygon spike's Python model
// (scratchpad geofence-polygon-spike/gen_fixtures.py); the Android SDK consumes the same values
// from test-vectors-geometry-latlon.json. Regenerate there — do not hand-edit values.
import CioInternalCommon
import Foundation

struct PolygonGeometryFixture {
    struct Sample {
        let point: LocationData
        let inside: Bool
        let signedEdgeDistance: Double
        let note: String
    }

    let name: String
    let vertices: [LocationData]
    let samples: [Sample]

    /// Covers centroid-reference drift between fixture synthesis and the SDK projection.
    static let toleranceMeters = 0.5
}

let polygonGeometryFixtures: [PolygonGeometryFixture] = [
    PolygonGeometryFixture(
        name: "square400",
        vertices: [LocationData(latitude: 31.36820136, longitude: 74.16789342), LocationData(latitude: 31.36820136, longitude: 74.17210658), LocationData(latitude: 31.37179864, longitude: 74.17210658), LocationData(latitude: 31.37179864, longitude: 74.16789342)],
        samples: [
            PolygonGeometryFixture.Sample(point: LocationData(latitude: 31.37, longitude: 74.17), inside: true, signedEdgeDistance: 200.0, note: "center"),
            PolygonGeometryFixture.Sample(point: LocationData(latitude: 31.37134898, longitude: 74.17157993), inside: true, signedEdgeDistance: 50.0, note: "deep interior"),
            PolygonGeometryFixture.Sample(point: LocationData(latitude: 31.37, longitude: 74.17205391), inside: true, signedEdgeDistance: 5.0, note: "5m inside edge"),
            PolygonGeometryFixture.Sample(point: LocationData(latitude: 31.37, longitude: 74.17215924), inside: false, signedEdgeDistance: -5.0, note: "5m outside edge"),
            PolygonGeometryFixture.Sample(point: LocationData(latitude: 31.37178965, longitude: 74.17209604), inside: true, signedEdgeDistance: 1.0, note: "near vertex inside"),
            PolygonGeometryFixture.Sample(point: LocationData(latitude: 31.37, longitude: 74.16726145), inside: false, signedEdgeDistance: -60.0, note: "annulus (in covering circle, outside polygon)"),
            PolygonGeometryFixture.Sample(point: LocationData(latitude: 31.36190611, longitude: 74.17), inside: false, signedEdgeDistance: -700.0, note: "far outside")
        ]
    ),
    PolygonGeometryFixture(
        name: "L_shape",
        vertices: [LocationData(latitude: 31.36820136, longitude: 74.16789342), LocationData(latitude: 31.36820136, longitude: 74.17210658), LocationData(latitude: 31.37, longitude: 74.17210658), LocationData(latitude: 31.37, longitude: 74.17), LocationData(latitude: 31.37179864, longitude: 74.17), LocationData(latitude: 31.37179864, longitude: 74.16789342)],
        samples: [
            PolygonGeometryFixture.Sample(point: LocationData(latitude: 31.37089932, longitude: 74.16894671), inside: true, signedEdgeDistance: 100.0, note: "upper arm interior"),
            PolygonGeometryFixture.Sample(point: LocationData(latitude: 31.36910068, longitude: 74.17105329), inside: true, signedEdgeDistance: 100.0, note: "lower arm interior"),
            PolygonGeometryFixture.Sample(point: LocationData(latitude: 31.37089932, longitude: 74.17105329), inside: false, signedEdgeDistance: -100.0, note: "NOTCH: inside covering circle, outside polygon"),
            PolygonGeometryFixture.Sample(point: LocationData(latitude: 31.36910068, longitude: 74.17005266), inside: true, signedEdgeDistance: 100.0, note: "5m inside notch edge (lower arm)"),
            PolygonGeometryFixture.Sample(point: LocationData(latitude: 31.37089932, longitude: 74.16994734), inside: true, signedEdgeDistance: 5.0, note: "5m inside notch edge (upper arm)"),
            PolygonGeometryFixture.Sample(point: LocationData(latitude: 31.37008993, longitude: 74.17010533), inside: false, signedEdgeDistance: -10.0, note: "just outside notch corner"),
            PolygonGeometryFixture.Sample(point: LocationData(latitude: 31.36824632, longitude: 74.16794609), inside: true, signedEdgeDistance: 5.0, note: "near outer vertex inside")
        ]
    ),
    PolygonGeometryFixture(
        name: "strip1000x150",
        vertices: [LocationData(latitude: 31.36932551, longitude: 74.16473356), LocationData(latitude: 31.36932551, longitude: 74.17526644), LocationData(latitude: 31.37067449, longitude: 74.17526644), LocationData(latitude: 31.37067449, longitude: 74.16473356)],
        samples: [
            PolygonGeometryFixture.Sample(point: LocationData(latitude: 31.37, longitude: 74.17), inside: true, signedEdgeDistance: 75.0, note: "center"),
            PolygonGeometryFixture.Sample(point: LocationData(latitude: 31.37062953, longitude: 74.17), inside: true, signedEdgeDistance: 5.0, note: "5m inside long edge"),
            PolygonGeometryFixture.Sample(point: LocationData(latitude: 31.37071946, longitude: 74.17), inside: false, signedEdgeDistance: -5.0, note: "5m outside long edge"),
            PolygonGeometryFixture.Sample(point: LocationData(latitude: 31.37, longitude: 74.17521377), inside: true, signedEdgeDistance: 5.0, note: "5m inside short edge"),
            PolygonGeometryFixture.Sample(point: LocationData(latitude: 31.37359729, longitude: 74.17), inside: false, signedEdgeDistance: -325.0, note: "annulus above strip")
        ]
    ),
    PolygonGeometryFixture(
        name: "tri150",
        vertices: [LocationData(latitude: 31.36955034, longitude: 74.16921003), LocationData(latitude: 31.36955034, longitude: 74.17078997), LocationData(latitude: 31.37071946, longitude: 74.17)],
        samples: [
            PolygonGeometryFixture.Sample(point: LocationData(latitude: 31.37, longitude: 74.17), inside: true, signedEdgeDistance: 39.978, note: "interior"),
            PolygonGeometryFixture.Sample(point: LocationData(latitude: 31.36959531, longitude: 74.17), inside: true, signedEdgeDistance: 5.0, note: "5m inside base"),
            PolygonGeometryFixture.Sample(point: LocationData(latitude: 31.36950537, longitude: 74.17), inside: false, signedEdgeDistance: -5.0, note: "5m outside base"),
            PolygonGeometryFixture.Sample(point: LocationData(latitude: 31.37053959, longitude: 74.1707373), inside: false, signedEdgeDistance: -50.639, note: "outside near slanted edge")
        ]
    )
]
