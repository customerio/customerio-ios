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
    // Signing fixes the environment for the life of the process, so it's read once
    private static let cachedEnvironment: ApnsEnvironment? = {
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        let profileUrl = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision")
        return environment(
            isSimulator: isSimulator,
            isRunningOnMac: ProcessInfo.processInfo.isMacCatalystApp,
            profile: profileUrl.flatMap { try? Data(contentsOf: $0) }
        )
    }()

    var environment: ApnsEnvironment? {
        Self.cachedEnvironment
    }

    /// Resolves the environment from the app's embedded provisioning profile.
    /// - Simulators only get sandbox tokens.
    /// - With a profile (development, ad hoc, enterprise), its `aps-environment` entitlement decides.
    /// - Without one on an iPhone or iPad, the app came from the App Store or TestFlight, which use production.
    /// - Otherwise (on a Mac, where the profile is elsewhere or absent; a profile without push; an unreadable profile) it's nil.
    static func environment(isSimulator: Bool, isRunningOnMac: Bool, profile: Data?) -> ApnsEnvironment? {
        if isSimulator {
            return .sandbox
        }
        guard let profile else {
            return isRunningOnMac ? nil : .production
        }

        switch apsEnvironmentEntitlement(inProfile: profile) {
        case "development":
            return .sandbox
        case "production":
            return .production
        default:
            return nil
        }
    }

    // The profile is a signed CMS envelope with its plist stored as plain text, so the plist is cut out of it
    private static func apsEnvironmentEntitlement(inProfile profile: Data) -> String? {
        guard let start = profile.range(of: Data("<?xml".utf8)),
              let end = profile.range(of: Data("</plist>".utf8), in: start.upperBound ..< profile.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: profile[start.lowerBound ..< end.upperBound], format: nil),
              let entitlements = (plist as? [String: Any])?["Entitlements"] as? [String: Any]
        else {
            return nil
        }

        return entitlements["aps-environment"] as? String
    }
}
