import CioInternalCommon
import Foundation

/// Stub for tests that need to control whether the user is considered identified.
final class IdentificationStateStub: IdentificationStateProviding {
    var isIdentified: Bool

    init(isIdentified: Bool = false) {
        self.isIdentified = isIdentified
    }
}
