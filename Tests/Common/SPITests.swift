@_spi(Internal) import CioInternalCommon
import SharedTests
import XCTest

/// Includes compile-time checks and validations for internal APIs marked with `@_spi(Internal)`.
/// These tests simulate usage by trusted internal consumers (e.g., Flutter or React Native plugins), and verify that default
/// implementations or internal contracts remain safe and stable.
///
/// These tests should NOT be used to validate public-facing API behavior.
/// Use `APITest` for that instead.
final class SPITests: UnitTest {
    /// Validates that a conforming type does not need to implement the `@_spi(Internal)` method
    /// `setDeepLinkCallback(_:)` directly, and can rely on default implementation provided via protocol extension.
    ///
    /// This ensures that internal consumers (with SPI access) can conform to `DeepLinkUtil` without
    /// breaking when protocol requirements change.
    func test_DeepLinkUtil_conformance_withDefaultSPIImplementation() {
        class Stub: DeepLinkUtil {
            func handleDeepLink(_ deepLinkUrl: URL) {}
        }

        _ = Stub() // Avoid unused warning
    }
}
