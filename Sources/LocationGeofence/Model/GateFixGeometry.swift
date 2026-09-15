import Foundation

/// What the contradiction gate measured a gated fix against, grouped so the record can carry
/// every measurement the analysis needs without exceeding the parameter-count limit. Dropping one
/// instead would be the wrong trade: `rad` is what buckets a drive by fence size, and `age` and
/// `acc` are the two reasons a gate declines to refuse.
struct GateFixGeometry {
    let distanceFromCenter: Double
    let radius: Double
    let accuracy: Double
    let fixAge: TimeInterval

    /// Negative is inside. Signed, unlike the refusal record's floored edge: which side the fix
    /// fell on is the question this record exists to answer.
    var signedEdgeDistance: Double { distanceFromCenter - radius }
}
