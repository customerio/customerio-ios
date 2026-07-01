import CioInternalCommon
import Foundation

/// Thread-safe holder for the two values that gate Live Activity reporting: the currently
/// identified user id (`nil` while anonymous or logged out) and the latest APNs device token.
///
/// Shared by `LiveActivityRegistrar` (which decides when to register) and `LiveActivityReporter`
/// (which gates every event on it), so both read a single source of truth without a dependency cycle.
final class LiveActivityIdentity: @unchecked Sendable {
    private let _userId = Synchronized<String?>(nil)
    private let _deviceToken = Synchronized<String?>(nil)

    var userId: String? {
        get { _userId.wrappedValue }
        set { _userId.wrappedValue = newValue }
    }

    var deviceToken: String? {
        get { _deviceToken.wrappedValue }
        set { _deviceToken.wrappedValue = newValue }
    }
}
