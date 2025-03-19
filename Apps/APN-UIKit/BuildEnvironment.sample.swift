import Foundation

struct BuildEnvironment {
    enum BuildInfo {
        static let buildTimestamp: TimeInterval = Date().timeIntervalSince1970
    }

    enum CustomerIO {
        static let cdpApiKey: String = "CUSTOMERIO_WORKSPACE_CDP_API_KEY"
        static let siteId: String = "CUSTOMERIO_WORKSPACE_SITE_ID"
        static let workspaceName: String = "CUSTOMERIO_WORKSPACE_NAME"
        static let sdkVersion: String = ""
    }

    enum GitMetadata {
        static let branchName: String = "" // Current branch name
        static let commitsAheadCount: String = "" // Number of commits ahead of the last tag
        static let commitHash: String = "" // Latest commit hash
    }
}
