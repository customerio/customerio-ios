#if os(iOS)
import SwiftUI

/// A resizable image resolved from `CIOAssetLibrary` by key.
///
/// Renders `Color.clear` when the key is absent or the library is a null instance.
/// Reads the library from the environment via `\.cioAssetLibrary`.
struct CIOAssetImage: View {
    let key: String

    @Environment(\.cioAssetLibrary) private var assetLibrary

    var body: some View {
        if let url = assetLibrary.url(for: key),
           let uiImage = UIImage(contentsOfFile: url.path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
        } else {
            Color.clear
        }
    }
}

/// A logo resolved from `CIOAssetLibrary` by key, with a text name as fallback.
///
/// Used both for the app-level brand (via ``init(appBranding:)``) and for per-activity
/// logos such as a sports league (pass `logoKey`/`name` directly). Reads the library
/// from the environment via `\.cioAssetLibrary`.
struct CIOBrandingView: View {
    let logoKey: String?
    let name: String
    /// When `true`, renders a lockup of the logo **and** the name side-by-side.
    /// When `false` (default), the logo alone is shown if it resolves, otherwise the name.
    let showsName: Bool

    @Environment(\.cioAssetLibrary) private var assetLibrary

    /// Renders the app-level branding configured via
    /// `CIOLiveActivitiesTemplates.configure(appGroup:branding:)`. When no branding was
    /// supplied, shows nothing.
    init(appBranding: CIOActivityBranding?, showsName: Bool = false) {
        self.init(logoKey: appBranding?.logoKey, name: appBranding?.name ?? "", showsName: showsName)
    }

    init(logoKey: String?, name: String, showsName: Bool = false) {
        self.logoKey = logoKey
        self.name = name
        self.showsName = showsName
    }

    var body: some View {
        if let logoKey,
           let url = assetLibrary.url(for: logoKey),
           let uiImage = UIImage(contentsOfFile: url.path) {
            if showsName {
                HStack(spacing: 6) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                }
            } else {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            }
        } else {
            Text(name)
                .font(.caption.bold())
        }
    }
}
#endif
