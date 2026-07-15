@testable import CioMessagingInbox
import CoreGraphics
import SwiftUI
import XCTest

/// Coverage for the branding-SVG bell glyph (`InboxBellIcon`, parsing via vendored SVGPath + fit) and
/// the branding-driven bell position mapping — the pure, non-SwiftUI-rendered pieces of the overlay,
/// unit-testable without a host.
@available(iOS 13.0, *)
final class InboxBellIconTests: XCTestCase {
    // MARK: - InboxBellIcon (branding SVG → fitted Shape)

    func test_bellIcon_givenSVG_thenFitsWithinTargetRectAspectPreserved() {
        // viewBox 24×25 (taller than wide), one triangle path.
        let svg = #"<svg viewBox="0 0 24 25"><path d="M0 0 L24 0 L24 25 Z"/></svg>"#
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let path = InboxBellIcon(svg: svg).path(in: rect)

        XCTAssertFalse(path.isEmpty)
        let bounds = path.boundingRect
        // Exact fitted bounds (not just "within rect", which a wrong stretch would also satisfy).
        // 24×25 into 100×100 → scale = min(100/24, 100/25) = 4; scaled = 96×100, centered → x offset
        // = (100-96)/2 = 2, y offset = 0. Asserting these catches an incorrect non-uniform stretch.
        XCTAssertEqual(bounds.minX, 2, accuracy: 0.5)
        XCTAssertEqual(bounds.minY, 0, accuracy: 0.5)
        XCTAssertEqual(bounds.width, 96, accuracy: 0.5)
        XCTAssertEqual(bounds.height, 100, accuracy: 0.5)
    }

    func test_bellIcon_givenMultiplePaths_thenParsesAll() {
        let svg = #"<svg viewBox="0 0 24 25"><path d="M0 0 L10 0 L10 10 Z"/><path d="M12 12 L20 12 L20 20 Z"/></svg>"#
        XCTAssertTrue(InboxBellIcon.canRender(svg))
        XCTAssertFalse(InboxBellIcon(svg: svg).path(in: CGRect(x: 0, y: 0, width: 50, height: 50)).isEmpty)
    }

    func test_bellIcon_givenNoPathsOrGarbage_thenCannotRender() {
        XCTAssertFalse(InboxBellIcon.canRender("<svg></svg>"))
        XCTAssertFalse(InboxBellIcon.canRender("not an svg"))
        XCTAssertFalse(InboxBellIcon.canRender(""))
    }

    func test_bellIcon_givenRealBrandingBellPath_thenRenders() {
        // A path lifted from the actual branding floatingIcon.svg (exponent + signed coords).
        let svg = #"<svg width="24" height="25" viewBox="0 0 24 25"><path fill-rule="evenodd" d="M9.05889 19.1249V19.9686C9.05889 21.3666 10.1922 22.4998 11.5901 22.4998C12.9881 22.4998 14.1214 21.3666 14.1214 19.9686V19.1249H15.8088V19.9686C15.8088 22.2986 13.9201 24.1873 11.5901 24.1873C9.26019 24.1873 7.3714 22.2986 7.3714 19.9686V19.1249H9.05889Z"/></svg>"#
        XCTAssertTrue(InboxBellIcon.canRender(svg))
    }

    // MARK: - InboxBellPosition

    func test_bellPosition_givenBrandingStrings_thenMapsToAlignment() {
        XCTAssertEqual(InboxBellPosition.resolve("bottom-right").alignment, .bottomTrailing)
        XCTAssertEqual(InboxBellPosition.resolve("bottom-left").alignment, .bottomLeading)
        XCTAssertEqual(InboxBellPosition.resolve("top-right").alignment, .topTrailing)
        XCTAssertEqual(InboxBellPosition.resolve("top-left").alignment, .topLeading)
    }

    func test_bellPosition_rawValuesMatchWebStrings() {
        XCTAssertEqual(InboxBellPosition.bottomRight.rawValue, "bottom-right")
        XCTAssertEqual(InboxBellPosition.bottomLeft.rawValue, "bottom-left")
        XCTAssertEqual(InboxBellPosition.topRight.rawValue, "top-right")
        XCTAssertEqual(InboxBellPosition.topLeft.rawValue, "top-left")
    }

    func test_bellPosition_givenNilOrUnknown_thenDefaultsToBottomRight() {
        XCTAssertEqual(InboxBellPosition.resolve(nil), .bottomRight)
        XCTAssertEqual(InboxBellPosition.resolve("somewhere"), .bottomRight)
        // Exact-match only — no case/format normalization (matches web's `switch(position)`).
        XCTAssertEqual(InboxBellPosition.resolve("BOTTOM-LEFT"), .bottomRight)
    }
}
