import CioInternalCommon
import Foundation

struct BuildInfoMetadata: CustomStringConvertible {
    let sdkVersion: String
    let appVersion: String
    let buildDate: String
    let gitMetadata: String
    let defaultWorkspace: String
    let language: String
    let uiFramework: String
    let sdkIntegration: String

    init() {
        self.sdkVersion = BuildInfoMetadata.resolveValidOrElse(BuildEnvironment.CustomerIO.sdkVersion) {
            "\(SdkVersion.version)-\(BuildInfoMetadata.resolveValidOrElse(BuildEnvironment.GitMetadata.commitsAheadCount) { "as-source" })"
        }
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        self.buildDate = BuildInfoMetadata.formatBuildDateWithRelativeTime(timestamp: BuildEnvironment.BuildInfo.buildTimestamp)
        let branchName = BuildEnvironment.GitMetadata.branchName
        let commitHash = BuildEnvironment.GitMetadata.commitHash
        self.gitMetadata = "\(BuildInfoMetadata.resolveValidOrElse(branchName) { "development build" })-\(BuildInfoMetadata.resolveValidOrElse(commitHash) { "untracked" })"
        self.defaultWorkspace = BuildInfoMetadata.resolveValidOrElse(BuildEnvironment.CustomerIO.workspaceName)
        self.language = BuildInfoMetadata.resolveValidOrElse("Swift")
        self.uiFramework = BuildInfoMetadata.resolveValidOrElse("UIKit (Storyboard)")
        self.sdkIntegration = BuildInfoMetadata.resolveValidOrElse("Swift Package Manager (SPM)")
    }

    var asSortedKeyValuePairs: [(String, String)] {
        [
            "SDK Version": sdkVersion,
            "App Version": appVersion,

            "Build Date": buildDate,
            "Branch": gitMetadata,
            "Default Workspace": defaultWorkspace,
            "Language": language,
            "UI Framework": uiFramework,
            "SDK Integration": sdkIntegration
        ].sorted(by: { $0.0 < $1.0 })
    }

    var description: String {
        var res = ""
        for (key, value) in asSortedKeyValuePairs {
            res += "\(key): \(value)\n"
        }
        return res
    }
}

extension BuildInfoMetadata {
    static func resolveValidOrElse(_ text: String?, _ fallback: () -> String = { "unknown" }) -> String {
        guard let text = text, !text.isEmpty else {
            return fallback()
        }
        return text
    }

    static func formatBuildDateWithRelativeTime(timestamp: TimeInterval) -> String {
        let buildDate = Date(timeIntervalSince1970: timestamp)
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let formattedDate = dateFormatter.string(from: buildDate)

        let daysAgo = daysSince(date: buildDate)
        let relativeTime = daysAgo == 0 ? "(Today)" : "(\(daysAgo) days ago)"

        return "\(formattedDate) \(relativeTime)"
    }

    static func daysSince(date: Date) -> Int {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfBuildDate = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: startOfBuildDate, to: startOfToday).day ?? 0
    }
}
