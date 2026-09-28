import Foundation

/// The raw value is the stable log token; `prose` is for humans.
enum ContradictionGateNoFixReason: String, CaseIterable {
    case noFixAvailable = "no_fix_available"
    case invalidCoordinate = "invalid_coordinate"

    var prose: String {
        switch self {
        case .noFixAvailable: return "no fix to judge it against"
        case .invalidCoordinate: return "the only fix is at an unusable coordinate"
        }
    }
}

struct GateFixGeometry {
    let distanceFromCenter: Double
    let radius: Double
    let accuracy: Double
    let fixAge: TimeInterval

    /// Negative is inside (the circle convention).
    var signedEdgeDistance: Double { distanceFromCenter - radius }
}
