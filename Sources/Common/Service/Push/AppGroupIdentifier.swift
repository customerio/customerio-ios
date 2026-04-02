import Foundation

/// Customer.io shared App Group string: `group.{main_app_bundle_id}.cio` (entitlements + `FileManager`).
///
/// In an extension, `Bundle.main.bundleIdentifier` is the extension id; we strip known suffixes so it matches the main app.
public enum AppGroupIdentifier {
    public static let cioSuffix = "cio"

    private static let extensionBundleSuffixes: [String] = [
        ".richpush",
        ".NotificationServiceExtension",
        ".NotificationService",
        ".richPush"
    ]

    /// `group.{mainAppBundleId}.cio` — use when you already have the main app bundle id.
    public static func identifier(forMainAppBundleId mainAppBundleId: String) -> String {
        "group.\(mainAppBundleId).\(cioSuffix)"
    }

    /// Same string from **any** target: pass `Bundle.main.bundleIdentifier` (main app or extension).
    public static func identifier(forProcessBundleIdentifier bundleIdentifier: String?) -> String? {
        guard let mainId = mainAppBundleId(fromProcessBundleIdentifier: bundleIdentifier) else { return nil }
        return identifier(forMainAppBundleId: mainId)
    }

    private static func mainAppBundleId(fromProcessBundleIdentifier bundleIdentifier: String?) -> String? {
        guard var id = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
            return nil
        }
        for suffix in extensionBundleSuffixes where id.hasSuffix(suffix) {
            id = String(id.dropLast(suffix.count))
            break
        }
        return id
    }
}
