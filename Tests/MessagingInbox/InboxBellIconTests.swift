@testable import CioMessagingInbox
import CoreGraphics
import SwiftUI
import XCTest

/// Coverage for the branding-SVG bell glyph (`InboxBellGlyph.build` extraction via vendored SVGPath +
/// `InboxBellIcon` fit) and the branding-driven bell position mapping — the pure, non-SwiftUI-rendered
/// pieces of the overlay, unit-testable without a host.
final class InboxBellIconTests: XCTestCase {
    // MARK: - InboxBellGlyph / InboxBellIcon (branding SVG → fitted Shape)

    func test_bellIcon_givenSVG_thenFitsWithinTargetRectAspectPreserved() throws {
        // viewBox 24×25 (taller than wide), one triangle path.
        let svg = #"<svg viewBox="0 0 24 25"><path d="M0 0 L24 0 L24 25 Z"/></svg>"#
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let glyph = try XCTUnwrap(InboxBellGlyph.build(fromSVG: svg))
        let subpath = try XCTUnwrap(glyph.subpaths.first).path
        let path = InboxBellIcon(subpath: subpath, viewBox: glyph.viewBox).path(in: rect)

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

    func test_bellIcon_givenSingleQuotedAttributes_thenParses() throws {
        // Branding markup (and the `InboxBrandingTest` fixture) use single-quoted attributes. The
        // extractor must accept them, otherwise the overlay silently falls back to the bundled bell.
        let svg = "<svg viewBox='0 0 24 25'><path d='M0 0 L24 0 L24 25 Z'/></svg>"
        let glyph = try XCTUnwrap(InboxBellGlyph.build(fromSVG: svg))
        let subpath = try XCTUnwrap(glyph.subpaths.first).path
        XCTAssertFalse(InboxBellIcon(subpath: subpath, viewBox: glyph.viewBox).path(in: CGRect(x: 0, y: 0, width: 50, height: 50)).isEmpty)
    }

    func test_bellIcon_givenMultiplePaths_thenKeepsThemSeparate() throws {
        let svg = #"<svg viewBox="0 0 24 25"><path d="M0 0 L10 0 L10 10 Z"/><path d="M12 12 L20 12 L20 20 Z"/></svg>"#
        let glyph = try XCTUnwrap(InboxBellGlyph.build(fromSVG: svg))
        // Each <path> is kept as its own entry so it can be filled independently (MBL-2123).
        XCTAssertEqual(glyph.subpaths.count, 2)
        let subpath = try XCTUnwrap(glyph.subpaths.first).path
        XCTAssertFalse(InboxBellIcon(subpath: subpath, viewBox: glyph.viewBox).path(in: CGRect(x: 0, y: 0, width: 50, height: 50)).isEmpty)
    }

    func test_bellIcon_givenNoPathsOrGarbage_thenReturnsNil() {
        XCTAssertNil(InboxBellGlyph.build(fromSVG: "<svg></svg>"))
        XCTAssertNil(InboxBellGlyph.build(fromSVG: "not an svg"))
        XCTAssertNil(InboxBellGlyph.build(fromSVG: ""))
    }

    func test_bellIcon_givenRealBrandingBellPath_thenBuilds() {
        // A path lifted from the actual branding floatingIcon.svg (exponent + signed coords).
        let svg = #"<svg width="24" height="25" viewBox="0 0 24 25"><path fill-rule="evenodd" d="M9.05889 19.1249V19.9686C9.05889 21.3666 10.1922 22.4998 11.5901 22.4998C12.9881 22.4998 14.1214 21.3666 14.1214 19.9686V19.1249H15.8088V19.9686C15.8088 22.2986 13.9201 24.1873 11.5901 24.1873C9.26019 24.1873 7.3714 22.2986 7.3714 19.9686V19.1249H9.05889Z"/></svg>"#
        XCTAssertNotNil(InboxBellGlyph.build(fromSVG: svg))
    }

    // MARK: - Fill-rule (MBL-2123): honor the source SVG's declared rule instead of forcing even-odd

    func test_bellIcon_givenEvenOddFillRule_thenUsesEvenOddFill() throws {
        let svg = #"<svg viewBox="0 0 24 25"><path fill-rule="evenodd" d="M0 0 L24 0 L24 25 Z"/></svg>"#
        let glyph = try XCTUnwrap(InboxBellGlyph.build(fromSVG: svg))
        XCTAssertTrue(try XCTUnwrap(glyph.subpaths.first).usesEvenOddFill)
    }

    func test_bellIcon_givenSingleQuotedEvenOddFillRule_thenUsesEvenOddFill() throws {
        let svg = "<svg viewBox='0 0 24 25'><path fill-rule='evenodd' d='M0 0 L24 0 L24 25 Z'/></svg>"
        let glyph = try XCTUnwrap(InboxBellGlyph.build(fromSVG: svg))
        XCTAssertTrue(try XCTUnwrap(glyph.subpaths.first).usesEvenOddFill)
    }

    func test_bellIcon_givenCssStyleEvenOddFillRule_thenUsesEvenOddFill() throws {
        let svg = #"<svg viewBox="0 0 24 25"><path style="fill-rule: evenodd" d="M0 0 L24 0 L24 25 Z"/></svg>"#
        let glyph = try XCTUnwrap(InboxBellGlyph.build(fromSVG: svg))
        XCTAssertTrue(try XCTUnwrap(glyph.subpaths.first).usesEvenOddFill)
    }

    func test_bellIcon_givenNoFillRule_thenDefaultsToNonZero() throws {
        // SVG/CSS default is nonzero — must NOT force even-odd (the pre-fix behavior).
        let svg = #"<svg viewBox="0 0 24 25"><path d="M0 0 L24 0 L24 25 Z"/></svg>"#
        let glyph = try XCTUnwrap(InboxBellGlyph.build(fromSVG: svg))
        XCTAssertFalse(try XCTUnwrap(glyph.subpaths.first).usesEvenOddFill)
    }

    func test_bellIcon_givenExplicitNonZeroFillRule_thenUsesNonZero() throws {
        let svg = #"<svg viewBox="0 0 24 25"><path fill-rule="nonzero" d="M0 0 L24 0 L24 25 Z"/></svg>"#
        let glyph = try XCTUnwrap(InboxBellGlyph.build(fromSVG: svg))
        XCTAssertFalse(try XCTUnwrap(glyph.subpaths.first).usesEvenOddFill)
    }

    func test_bellIcon_givenMixedFillRules_thenResolvesPerPath() throws {
        // Each <path> keeps its OWN rule (not one rule for the whole SVG): first evenodd, second nonzero.
        let svg = #"<svg viewBox="0 0 24 25"><path fill-rule="evenodd" d="M0 0 L10 0 L10 10 Z"/><path fill-rule="nonzero" d="M12 12 L20 12 L20 20 Z"/></svg>"#
        let glyph = try XCTUnwrap(InboxBellGlyph.build(fromSVG: svg))
        XCTAssertEqual(glyph.subpaths.map(\.usesEvenOddFill), [true, false])
    }

    func test_bellIcon_givenRootSvgFillRule_thenPathsInheritIt() throws {
        // A <path> with no fill-rule inherits the root <svg>'s declared rule.
        let svg = #"<svg fill-rule="evenodd" viewBox="0 0 24 25"><path d="M0 0 L24 0 L24 25 Z"/></svg>"#
        let glyph = try XCTUnwrap(InboxBellGlyph.build(fromSVG: svg))
        XCTAssertTrue(try XCTUnwrap(glyph.subpaths.first).usesEvenOddFill)
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
