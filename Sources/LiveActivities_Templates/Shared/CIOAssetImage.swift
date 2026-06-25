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
            let uiImage = UIImage(contentsOfFile: url.path)
        {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
        } else {
            Color.clear
        }
    }
}

/// Brand logo resolved from `CIOAssetLibrary`, with the brand name as a text fallback.
///
/// Reads the library from the environment via `\.cioAssetLibrary`.
struct CIOBrandingView: View {

    let branding: CIOActivityBranding

    @Environment(\.cioAssetLibrary) private var assetLibrary

    var body: some View {
        if let logoKey = branding.logoKey,
            let url = assetLibrary.url(for: logoKey),
            let uiImage = UIImage(contentsOfFile: url.path)
        {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
        } else {
            Text(branding.name)
                .font(.caption.bold())
        }
    }
}
#endif
