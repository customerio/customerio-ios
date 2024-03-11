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

    var menuTitle: String {
        // TODO: menu title for each screen
        switch self {
        case .sampleAppIntro:
            SampleAppIntro.title.menuTitle
        case .install:
            ""
        case .setup:
            ""
        case .customerIOIntro:
            ""
        case .identify:
            ""
        case .howToTestIdentify:
            ""
        case .profileAttributes:
            ""
        case .howToTestProfileAttributes:
            ""
        case .deviceAttributes:
            ""
        case .howToTestDeviceAttributes:
            ""
        case .track:
            ""
        case .howToTestTrack:
            ""
        }
    }

    static let preInitializationLinks: [Self] = [
        .sampleAppIntro,
        .install,
        .setup
    ]

    static let preIdentifyLinks: [Self] = [
        .sampleAppIntro,
        .install,
        .setup,
        .customerIOIntro,
        .identify,
        .howToTestIdentify
    ]
}
