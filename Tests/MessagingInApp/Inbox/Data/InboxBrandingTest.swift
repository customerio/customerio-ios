@testable import CioMessagingInApp
import Foundation
import XCTest

class InboxBrandingTest: XCTestCase {
    /// Trimmed copy of the real captured `/api/v1/branding` response. Mirrors the production shape:
    /// `patterns.inbox.floatingIcon { background, color }` plus the rest of the inbox chrome.
    /// NOTE: `patterns.modes.dark` is intentionally ABSENT, matching this workspace's server response.
    private let brandingJSON = #"""
    {
      "theme": {
        "text": { "text": { "fontSize": 16, "color": "#000000" } },
        "button": { "background": { "color": "#000000" }, "border": { "radius": 4 } }
      },
      "patterns": {
        "inbox": {
          "floatingIcon": {
            "background": "#000000",
            "color": "#ffffff"
          },
          "background": "#ffffff",
          "cornerRadius": 8,
          "borderColor": "#d9d9d9",
          "dividerColor": "#d9d9d9",
          "shadow": { "color": "#00000026", "offsetX": 0, "offsetY": 2, "blur": 8 },
          "position": "bottom-right",
          "hoverBackground": "#f5f5f5",
          "unreadIndicator": {
            "showAlert": true,
            "text": { "fontSize": 8, "color": "#ffffff" },
            "background": "#e00000"
          }
        }
      }
    }
    """#

    private func parse(_ json: String) -> InboxBranding? {
        InboxBranding.from(jsonData: Data(json.utf8))
    }

    func test_from_whenRepresentativeFixture_expectFloatingIconParsed() {
        let branding = parse(brandingJSON)
        XCTAssertNotNil(branding)

        // Only the bell container/glyph colors are kept; the raw SVG markup is no longer carried.
        let icon = branding?.chrome.floatingIcon
        XCTAssertEqual(icon?.background, "#000000")
        XCTAssertEqual(icon?.color, "#ffffff")
    }

    func test_from_whenRepresentativeFixture_expectThemeParsed() {
        let theme = parse(brandingJSON)?.theme
        let text = theme?["text"] as? [String: Any]
        XCTAssertNotNil(text)
    }

    func test_from_whenRepresentativeFixture_expectInboxChromeParsed() {
        let chrome = parse(brandingJSON)?.chrome
        XCTAssertEqual(chrome?.background, "#ffffff")
        XCTAssertEqual(chrome?.cornerRadius, 8)
        XCTAssertEqual(chrome?.borderColor, "#d9d9d9")
        XCTAssertEqual(chrome?.dividerColor, "#d9d9d9")
        XCTAssertEqual(chrome?.position, "bottom-right")
        XCTAssertEqual(chrome?.hoverBackground, "#f5f5f5")

        XCTAssertEqual(chrome?.shadow?.color, "#00000026")
        XCTAssertEqual(chrome?.shadow?.offsetX, 0)
        XCTAssertEqual(chrome?.shadow?.offsetY, 2)
        XCTAssertEqual(chrome?.shadow?.blur, 8)

        XCTAssertEqual(chrome?.unreadIndicator?.showAlert, true)
        XCTAssertEqual(chrome?.unreadIndicator?.background, "#e00000")
        XCTAssertEqual(chrome?.unreadIndicator?.text?["fontSize"] as? Int, 8)
    }

    func test_from_whenDarkModeAbsent_expectNilDarkModePattern() {
        let branding = parse(brandingJSON)
        // `patterns.modes.dark` is absent in this workspace's response -> must be nil.
        XCTAssertNil(branding?.darkModePattern)
    }

    func test_from_whenDarkModePresent_expectParsed() {
        let json = #"""
        {
          "theme": {},
          "patterns": {
            "inbox": {},
            "modes": { "dark": { "background": "#111111" } }
          }
        }
        """#
        let branding = parse(json)
        XCTAssertEqual(branding?.darkModePattern?["background"] as? String, "#111111")
    }

    func test_from_whenKeysMissing_expectTolerantDefaults() {
        // Minimal payload: only a stub `patterns.inbox`. Every chrome field should be nil/empty,
        // never a crash.
        let branding = parse(#"{ "patterns": { "inbox": {} } }"#)
        XCTAssertNotNil(branding)
        XCTAssertNil(branding?.chrome.floatingIcon.background)
        XCTAssertNil(branding?.chrome.background)
        XCTAssertNil(branding?.chrome.shadow)
        XCTAssertNil(branding?.chrome.unreadIndicator)
        XCTAssertNil(branding?.darkModePattern)
        XCTAssertTrue(branding?.theme.isEmpty ?? false)
    }

    func test_from_whenNotJSONObject_expectNil() {
        XCTAssertNil(parse("[1, 2, 3]"))
    }
}
