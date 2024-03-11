import Foundation

enum InlineNavigationLink: String, Codable, CaseIterable {
    case sampleAppIntro,
         install,
         setup,
         customerIOIntro,
         identify,
         howToTestIdentify,
         profileAttributes,
         howToTestProfileAttributes,
         deviceAttributes,
         howToTestDeviceAttributes,
         track,
         howToTestTrack

    init?(fromUrl url: URL) {
        guard let link = Self(rawValue: url.absoluteString)
        else {
            return nil
        }

        self = link
    }
}
