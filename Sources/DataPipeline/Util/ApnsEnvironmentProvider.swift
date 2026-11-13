import Foundation

/// APNs environment that the app's push tokens are issued for.
/// Raw values are sent as the `apns_environment` device attribute.
enum ApnsEnvironment: String {
    case sandbox
    case production
}

/// Reads the APNs environment of the running app.
protocol ApnsEnvironmentProvider: AutoMockable {
    /// The environment, or nil when it can't be determined.
    var environment: ApnsEnvironment? { get }
}

// sourcery: InjectRegisterShared = "ApnsEnvironmentProvider"
class SdkApnsEnvironmentProvider: ApnsEnvironmentProvider {
    /// The provisioning profile embedded in the app bundle.
    enum EmbeddedProfile: Equatable {
        case missing
        /// Present, but unreadable or too large to be a real profile.
        case unusable
        case contents(Data)
    }

    // Typical profiles are 15-20 KB, and big teams add some. A file far larger isn't read.
    static let maxProfileSize = 1024 * 1024

    // Signing fixes the environment for the life of the process, so it's read once
    private static let cachedEnvironment: ApnsEnvironment? = {
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        return environment(
            isSimulator: isSimulator,
            isRunningOnMac: ProcessInfo.processInfo.isMacCatalystApp,
            profile: readProfile(at: Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"))
        )
    }()

    var environment: ApnsEnvironment? {
        Self.cachedEnvironment
    }

    /// Resolves the environment from the app's embedded provisioning profile.
    /// - Simulators only get sandbox tokens.
    /// - With a profile (development, ad hoc, enterprise), its `aps-environment` entitlement decides.
    /// - Without one on an iPhone or iPad, the app came from the App Store or TestFlight, which use production.
    /// - Otherwise (on a Mac, where the profile is elsewhere or absent; a profile without push; an unusable profile) it's nil.
    static func environment(isSimulator: Bool, isRunningOnMac: Bool, profile: EmbeddedProfile) -> ApnsEnvironment? {
        if isSimulator {
            return .sandbox
        }

        switch profile {
        case .missing:
            return isRunningOnMac ? nil : .production
        case .unusable:
            return nil
        case .contents(let data):
            guard data.count <= maxProfileSize else { return nil }

            switch apsEnvironmentEntitlement(inProfile: data) {
            case "development":
                return .sandbox
            case "production":
                return .production
            default:
                return nil
            }
        }
    }

    static func readProfile(at url: URL?) -> EmbeddedProfile {
        guard let url else {
            return .missing
        }
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              size <= maxProfileSize,
              let data = try? Data(contentsOf: url)
        else {
            return .unusable
        }

        return .contents(data)
    }

    // A byte search for the one value instead of a plist parse, so unexpected data can only give nil.
    // In a profile the key appears only in the Entitlements dictionary, so it's searched after that key.
    private static func apsEnvironmentEntitlement(inProfile profile: Data) -> String? {
        guard let entitlements = profile.range(of: Data("<key>Entitlements</key>".utf8)),
              let key = profile.range(of: Data("<key>aps-environment</key>".utf8), in: entitlements.upperBound ..< profile.endIndex),
              let open = profile.range(of: Data("<string>".utf8), in: key.upperBound ..< profile.endIndex),
              profile[key.upperBound ..< open.lowerBound].allSatisfy(isXmlWhitespace),
              let close = profile.range(of: Data("</string>".utf8), in: open.upperBound ..< profile.endIndex)
        else {
            return nil
        }

        return String(data: profile[open.upperBound ..< close.lowerBound], encoding: .utf8)
    }

    private static func isXmlWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D
    }
}
