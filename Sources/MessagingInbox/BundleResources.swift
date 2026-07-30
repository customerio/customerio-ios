import Foundation

/// Type token used to locate this module's framework bundle under CocoaPods (`Bundle(for:)`).
private final class CioInboxBundleToken {}

extension Bundle {
    /// The bundle that ships `CioMessagingInbox`'s resources (currently the fallback bell asset).
    ///
    /// Under Swift Package Manager this is the compiler-synthesized `Bundle.module`. `Bundle.module`
    /// is **SwiftPM-only** — it does not exist when the SDK is built via `CustomerIOMessagingInbox.podspec`
    /// (CocoaPods) and referencing it there fails to compile. This shim resolves the CocoaPods
    /// `resource_bundle` by name (with fallbacks) so the fallback bell loads and the pod builds on both.
    static var cioInboxResources: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        // CocoaPods emits the resources into a `<name>.bundle` alongside the framework. The key is
        // interpolated from `spec.module_name` in the podspec; try both the module name and the
        // pod name to be resilient to how CocoaPods resolves it.
        let candidateBundleNames = ["CioMessagingInbox_InboxAssets", "CustomerIOMessagingInbox_InboxAssets"]
        let frameworkBundle = Bundle(for: CioInboxBundleToken.self)
        let searchRoots = [
            frameworkBundle.resourceURL,
            frameworkBundle.bundleURL,
            Bundle.main.resourceURL,
            Bundle.main.bundleURL
        ].compactMap { $0 }

        for root in searchRoots {
            for name in candidateBundleNames {
                let url = root.appendingPathComponent("\(name).bundle")
                if let bundle = Bundle(url: url) {
                    return bundle
                }
            }
        }
        // Last resort: the framework's own bundle (covers assets embedded directly, e.g. static linkage).
        return frameworkBundle
        #endif
    }
}
