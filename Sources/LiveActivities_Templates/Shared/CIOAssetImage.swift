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

/// The app-level brand logo resolved from `CIOAssetLibrary` by key.
///
/// Renders the logo configured via `CIOLiveActivitiesTemplates.configure(appGroup:branding:)`,
/// or nothing when no branding/logo is available (branding is constant chrome — logo + colors —
/// not per-activity content). Reads the library from the environment via `\.cioAssetLibrary`.
struct CIOBrandingView: View {
    let logoKey: String?

    @Environment(\.cioAssetLibrary) private var assetLibrary

    init(appBranding: CIOActivityBranding?) {
        self.logoKey = appBranding?.logoKey
    }

    var body: some View {
        if let logoKey,
           let url = assetLibrary.url(for: logoKey),
           let uiImage = UIImage(contentsOfFile: url.path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
        }
    }
}
#endif
