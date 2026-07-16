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
@available(iOS 13.0, *)
struct InboxBellGlyph {
    let path: Path
    let viewBox: CGRect

    /// Builds a glyph from raw SVG markup (e.g. `<svg viewBox="0 0 24 25"><path d="…"/>…</svg>`), or
    /// nil when there is nothing renderable (no parseable `<path d>`) — the bell then falls back to
    /// the bundled default glyph. Malformed subpaths are skipped rather than failing the whole glyph.
    static func build(fromSVG svg: String) -> InboxBellGlyph? {
        let pathData = pathData(from: svg)
        guard !pathData.isEmpty else { return nil }
        var combined = Path()
        for data in pathData {
            // Vendored SVGPath (`Path(svgPath:)`); skip any malformed subpath rather than fail whole.
            if let subpath = try? Path(svgPath: data) {
                combined.addPath(subpath)
            }
        }
        guard !combined.isEmpty else { return nil }
        // Prefer the declared viewBox; otherwise use the path's own bounds as the coordinate space.
        return InboxBellGlyph(path: combined, viewBox: viewBox(from: svg) ?? combined.boundingRect)
    }

    // MARK: - SVG extraction (path data + viewBox); parsing delegated to vendored SVGPath

    /// Extracts every `<path … d="…">` value from the markup. Accepts single- OR double-quoted
    /// attributes — branding markup (and captured fixtures) use single quotes.
    private static func pathData(from svg: String) -> [String] {
        matches(in: svg, pattern: #"<path[^>]*\bd\s*=\s*["']([^"']*)["']"#)
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
}

/// Renders a pre-built ``InboxBellGlyph`` as a tint-able SwiftUI `Shape`, fitting it into the target
/// rect (centered, aspect-preserving). Parsing already happened in ``InboxBellGlyph/build(fromSVG:)``;
/// `path(in:)` only applies the fit transform, so it stays cheap on every layout pass.
///
/// Fill with `FillStyle(eoFill: true)`: CIO bell glyphs are authored with the even-odd rule (the bell
/// body is an outlined ring), matching the source SVG's `fill-rule="evenodd"`.
@available(iOS 13.0, *)
struct InboxBellIcon: Shape {
    /// The pre-built glyph to render.
    let glyph: InboxBellGlyph

    func path(in rect: CGRect) -> Path {
        let box = glyph.viewBox
        guard box.width > 0, box.height > 0 else { return Path() }
        // Fit the viewBox into rect, centered, preserving aspect ratio (scale then translate).
        let scale = min(rect.width / box.width, rect.height / box.height)
        let scaledWidth = box.width * scale
        let scaledHeight = box.height * scale
        let translateX = rect.minX + (rect.width - scaledWidth) / 2 - box.minX * scale
        let translateY = rect.minY + (rect.height - scaledHeight) / 2 - box.minY * scale
        let transform = CGAffineTransform(translationX: translateX, y: translateY)
            .scaledBy(x: scale, y: scale)
        return glyph.path.applying(transform)
    }
}
#endif
