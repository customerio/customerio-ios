import Foundation

// Log contracts for the contradiction gate's non-refusal outcomes, kept with the tail rather than
// in `Model/`.

/// Why the gate had no fix to judge an in-window event against. `prose` is for humans; the raw
/// value is the stable token.
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

/// What the gate measured a fix against, grouped to stay under the parameter-count limit.
struct GateFixGeometry {
    let distanceFromCenter: Double
    let radius: Double
    let accuracy: Double
    let fixAge: TimeInterval

    /// Negative is inside (the circle convention).
    var signedEdgeDistance: Double { distanceFromCenter - radius }
}
