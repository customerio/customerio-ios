import Foundation

/// Represents milliseconds.
/// `let 400Milliseconds: Milliseconds = 400`
public typealias Milliseconds = Double

extension Milliseconds {
    var toSeconds: TimeInterval {
        self / 1000
    }
}
