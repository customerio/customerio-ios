import Foundation

/// Provides the current identification state: whether the user is identified (logged in).
/// Used by the Location module to decide whether to sync location to the server.
public protocol IdentificationStateProviding: AnyObject {
    /// `true` when a profile has been identified (e.g. via identify or from existing session); `false` after reset/logout.
    var isIdentified: Bool { get }
}
