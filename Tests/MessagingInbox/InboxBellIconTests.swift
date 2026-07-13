@testable import CioMessagingInbox
import CoreGraphics
import SwiftUI
import XCTest

/// Coverage for the vector bell glyph (SVG path parsing + fit), the branding-driven bell position
/// mapping, and the panel detent convenience. These are the pure, non-SwiftUI-rendered pieces of the
/// overlay redesign, so they are unit-testable without a host.
@available(iOS 13.0, *)
final class InboxBellIconTests: XCTestCase {
    // MARK: - SVGPathParser

    func test_svgParser_givenSimpleClosedTriangle_thenBoundsMatch() {
        var path = Path()
        SVGPathParser.append(pathData: "M0 0L10 0L10 10Z", to: &path)

        XCTAssertFalse(path.isEmpty)
        let bounds = path.boundingRect
        XCTAssertEqual(bounds.minX, 0, accuracy: 0.001)
        XCTAssertEqual(bounds.minY, 0, accuracy: 0.001)
        XCTAssertEqual(bounds.maxX, 10, accuracy: 0.001)
        XCTAssertEqual(bounds.maxY, 10, accuracy: 0.001)
    }

    func test_svgParser_givenHorizontalAndVerticalCommands_thenTracksCurrentPoint() {
        var path = Path()
        SVGPathParser.append(pathData: "M2 3H8V9", to: &path)

        let bounds = path.boundingRect
        XCTAssertEqual(bounds.minX, 2, accuracy: 0.001)
        XCTAssertEqual(bounds.minY, 3, accuracy: 0.001)
        XCTAssertEqual(bounds.maxX, 8, accuracy: 0.001)
        XCTAssertEqual(bounds.maxY, 9, accuracy: 0.001)
    }

    func test_svgParser_givenSignsAndScientificNotation_thenParsesNumbers() {
        // `7.2075e-05` ≈ 0 and a leading `-1` exercise exponent + sign handling (both appear in the
        // real bell glyph). Correct parsing keeps the bounds at the authored extents.
        var path = Path()
        SVGPathParser.append(pathData: "M-1 0L7.2075e-05 5L10 5Z", to: &path)

        let bounds = path.boundingRect
        XCTAssertEqual(bounds.minX, -1, accuracy: 0.001)
        XCTAssertEqual(bounds.minY, 0, accuracy: 0.001)
        XCTAssertEqual(bounds.maxX, 10, accuracy: 0.001)
        XCTAssertEqual(bounds.maxY, 5, accuracy: 0.001)
    }

    func test_bellIcon_givenTargetRect_thenFitsCenteredAndAspectPreserved() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let path = InboxBellIcon().path(in: rect)

        XCTAssertFalse(path.isEmpty)
        let bounds = path.boundingRect
        // Scaled-to-fit + centered: must stay within the target rect (small epsilon for stroke math).
        XCTAssertGreaterThanOrEqual(bounds.minX, rect.minX - 0.5)
        XCTAssertGreaterThanOrEqual(bounds.minY, rect.minY - 0.5)
        XCTAssertLessThanOrEqual(bounds.maxX, rect.maxX + 0.5)
        XCTAssertLessThanOrEqual(bounds.maxY, rect.maxY + 0.5)
        // Aspect preserved: viewBox 24×25 is taller than wide, so in a square rect height >= width.
        XCTAssertGreaterThanOrEqual(bounds.height, bounds.width - 0.5)
    }

    // MARK: - InboxBellPosition

    func test_bellPosition_givenBrandingStrings_thenMapsToAlignment() {
        XCTAssertEqual(InboxBellPosition.resolve("bottom-right").alignment, .bottomTrailing)
        XCTAssertEqual(InboxBellPosition.resolve("bottom-left").alignment, .bottomLeading)
        XCTAssertEqual(InboxBellPosition.resolve("top-right").alignment, .topTrailing)
        XCTAssertEqual(InboxBellPosition.resolve("top-left").alignment, .topLeading)
    }

    func test_bellPosition_givenMixedCaseAndWhitespace_thenNormalizes() {
        XCTAssertEqual(InboxBellPosition.resolve("  BOTTOM-LEFT ").alignment, .bottomLeading)
    }

    func test_bellPosition_givenNilOrUnknown_thenDefaultsToBottomTrailing() {
        XCTAssertEqual(InboxBellPosition.resolve(nil).alignment, .bottomTrailing)
        XCTAssertEqual(InboxBellPosition.resolve("somewhere").alignment, .bottomTrailing)
    }

    func test_bellPosition_isTop() {
        XCTAssertTrue(InboxBellPosition.resolve("top-right").isTop)
        XCTAssertTrue(InboxBellPosition.resolve("top-left").isTop)
        XCTAssertFalse(InboxBellPosition.resolve("bottom-right").isTop)
        XCTAssertFalse(InboxBellPosition.resolve("bottom-left").isTop)
    }
}
