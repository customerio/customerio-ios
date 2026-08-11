import Foundation
#if canImport(SwiftUI)
import CoreGraphics
import SwiftUI

/// A pre-built bell glyph: the combined even-odd `Path` extracted from a branding SVG plus the source
/// `viewBox` it should be fitted into.
///
/// Built ONCE via ``build(fromSVG:)`` when branding resolves (held on `VisualInboxModel`), rather than
/// re-parsed on every render pass — and released together with the model when the inbox UI is torn
/// down, so the parsed glyph isn't retained process-wide after the inbox is gone.
///
/// Path parsing is delegated to the vendored `SVGPath` (see `Vendor/SVGPath`), which robustly handles
/// the full SVG path grammar. This type only extracts the `<path d="…">` elements + `viewBox` from the
/// markup and combines the paths.
struct InboxBellGlyph {
    /// One `<path>` element: its geometry (in viewBox coordinates) + the fill rule to apply to IT.
    struct Subpath {
        let path: Path
        /// Even-odd fill for this path: its declared `fill-rule` (`evenodd` → true), else the root
        /// `<svg>`'s, else nonzero (the SVG/CSS default). Resolved per-path so a glyph that mixes
        /// rules renders each path correctly — matching how a browser fills each `<path>` (MBL-2123),
        /// and matching Android which likewise honors the declared rule per path.
        let usesEvenOddFill: Bool
    }

    /// One entry per `<path>` element, filled **independently**. Merging all `<path>`s into a single
    /// `Path` and applying one fill rule flips winding parity where the paths overlap — punching
    /// spurious holes/solids that read as a malformed/heavier glyph (MBL-2123). Browsers fill each
    /// `<path>` on its own (with that path's own rule); stacking per-path fills with a uniform tint
    /// matches that.
    let subpaths: [Subpath]
    let viewBox: CGRect

    /// Builds a glyph from raw SVG markup (e.g. `<svg viewBox="0 0 24 25"><path d="…"/>…</svg>`), or
    /// nil when there is nothing renderable (no parseable `<path d>`) — the bell then falls back to
    /// the bundled default glyph. Malformed subpaths are skipped rather than failing the whole glyph.
    static func build(fromSVG svg: String) -> InboxBellGlyph? {
        let elements = pathElements(from: svg)
        guard !elements.isEmpty else { return nil }
        // A `<path>` with no `fill-rule` inherits the root `<svg>`'s, else nonzero (SVG/CSS default).
        let rootEvenOdd = rootSvgTag(from: svg).flatMap { fillRuleEvenOdd(in: $0) }
        // Keep each `<path>` separate so it can be filled independently, with its own fill rule.
        var subpaths: [Subpath] = []
        for element in elements {
            // Vendored SVGPath (`Path(svgPath:)`); skip any malformed subpath rather than fail whole.
            guard let data = pathDValue(in: element),
                  let path = try? Path(svgPath: data), !path.isEmpty else { continue }
            let usesEvenOdd = fillRuleEvenOdd(in: element) ?? rootEvenOdd ?? false
            subpaths.append(Subpath(path: path, usesEvenOddFill: usesEvenOdd))
        }
        guard !subpaths.isEmpty else { return nil }
        // Prefer the declared viewBox; otherwise use the union of the paths' bounds as the space.
        let fallbackBox = subpaths.reduce(CGRect.null) { $0.union($1.path.boundingRect) }
        return InboxBellGlyph(subpaths: subpaths, viewBox: viewBox(from: svg) ?? fallbackBox)
    }

    // MARK: - SVG extraction (path elements + viewBox + fill-rule); parsing delegated to vendored SVGPath

    /// The full opening tag of every `<path …>` element, so per-path attributes (`d`, `fill-rule`)
    /// can be read individually. Accepts single- OR double-quoted attributes.
    private static func pathElements(from svg: String) -> [String] {
        fullMatches(in: svg, pattern: #"<path\b[^>]*>"#)
    }

    /// The root `<svg …>` opening tag, if present (for a document-level `fill-rule` fallback).
    private static func rootSvgTag(from svg: String) -> String? {
        fullMatches(in: svg, pattern: #"<svg\b[^>]*>"#).first
    }

    /// The `d` attribute value within a single `<path>` element (single- or double-quoted).
    private static func pathDValue(in element: String) -> String? {
        matches(in: element, pattern: #"\bd\s*=\s*["']([^"']*)["']"#).first
    }

    /// Reads a `fill-rule` (attribute or CSS `style`) from a fragment: `evenodd` → true, `nonzero`
    /// → false, absent → nil (so the caller falls back to the root rule, then nonzero — the default).
    private static func fillRuleEvenOdd(in fragment: String) -> Bool? {
        guard let raw = matches(in: fragment, pattern: #"fill-rule\s*[=:]\s*["']?\s*(evenodd|nonzero)"#).first else { return nil }
        return raw.lowercased() == "evenodd"
    }

    /// Parses a `viewBox="minX minY width height"` attribute (single- or double-quoted), if present.
    private static func viewBox(from svg: String) -> CGRect? {
        guard let raw = matches(in: svg, pattern: #"\bviewBox\s*=\s*["']([^"']*)["']"#).first else { return nil }
        let parts = raw.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    /// Returns the first capture group of every match of `pattern` in `string`.
    private static func matches(in string: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsString = string as NSString
        var results: [String] = []
        regex.enumerateMatches(in: string, range: NSRange(location: 0, length: nsString.length)) { match, _, _ in
            if let match = match, match.numberOfRanges > 1 {
                results.append(nsString.substring(with: match.range(at: 1)))
            }
        }
        return results
    }

    /// Returns the whole matched substring of every match of `pattern` in `string` (e.g. a full
    /// `<path …>` opening tag), used to read per-element attributes.
    private static func fullMatches(in string: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let nsString = string as NSString
        var results: [String] = []
        regex.enumerateMatches(in: string, range: NSRange(location: 0, length: nsString.length)) { match, _, _ in
            if let match = match {
                results.append(nsString.substring(with: match.range))
            }
        }
        return results
    }
}

/// Renders a pre-built ``InboxBellGlyph`` as a tint-able SwiftUI `Shape`, fitting it into the target
/// rect (centered, aspect-preserving). Parsing already happened in ``InboxBellGlyph/build(fromSVG:)``;
/// `path(in:)` only applies the fit transform, so it stays cheap on every layout pass.
///
/// The caller fills each sub-path with `FillStyle(eoFill: subpath.usesEvenOddFill)` so the SVG's own
/// declared `fill-rule` is honored per-path (MBL-2123) rather than assuming even-odd.
struct InboxBellIcon: Shape {
    /// One sub-path from the glyph (viewBox coordinates). Rendered as its own filled shape.
    let subpath: Path
    /// The glyph's viewBox — shared across all sub-paths so they fit + align identically.
    let viewBox: CGRect

    func path(in rect: CGRect) -> Path {
        let box = viewBox
        guard box.width > 0, box.height > 0 else { return Path() }
        // Fit the viewBox into rect, centered, preserving aspect ratio (scale then translate).
        let scale = min(rect.width / box.width, rect.height / box.height)
        let scaledWidth = box.width * scale
        let scaledHeight = box.height * scale
        let translateX = rect.minX + (rect.width - scaledWidth) / 2 - box.minX * scale
        let translateY = rect.minY + (rect.height - scaledHeight) / 2 - box.minY * scale
        let transform = CGAffineTransform(translationX: translateX, y: translateY)
            .scaledBy(x: scale, y: scale)
        return subpath.applying(transform)
    }
}
#endif
