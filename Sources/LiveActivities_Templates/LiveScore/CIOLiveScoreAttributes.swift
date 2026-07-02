import CioLiveActivities_Attributes

#if os(iOS)
import ActivityKit

/// Attributes for the Live Score template.
///
/// Tracks a two-team match with real-time score updates and a freeform bottom label
/// (e.g. `"Starts in 15 Min"`, `"2nd half · 55:67"`, `"Final Score"`).
///
/// The `subtitle` slot is freeform and rendered verbatim; the SDK never composes it.
@available(iOS 17.2, *)
public struct CIOLiveScoreAttributes: CIOActivityAttribute {
    public static let identifier = "io.customer.liveactivities.livescore"

    // MARK: - Nested types

    public struct Team: Codable, Hashable, Sendable {
        /// Display name for the team.
        public var name: String
        /// Asset reference for the team logo (bundle name / asset key / URL), resolved via
        /// `CIOAssetLibrary`. `nil` falls back to the team name's initials.
        public var logo: String?

        public init(name: String, logo: String? = nil) {
            self.name = name
            self.logo = logo
        }
    }

    // MARK: - Static attributes

    public var activityInstanceId: String
    public var homeTeam: Team
    public var awayTeam: Team
    /// Asset reference for the league or app icon (bundle name / asset key / URL).
    public var image: String?

    public init(
        activityInstanceId: String,
        homeTeam: Team,
        awayTeam: Team,
        image: String? = nil
    ) {
        self.activityInstanceId = activityInstanceId
        self.homeTeam = homeTeam
        self.awayTeam = awayTeam
        self.image = image
    }

    // MARK: - Dynamic content state

    public struct ContentState: Codable, Hashable, Sendable {
        /// Home team score. `nil` pre-game.
        public var homeScore: Int?
        /// Away team score. `nil` pre-game.
        public var awayScore: Int?
        /// Freeform bottom label e.g. `"Starts in 15 Min"`, `"2nd half · 55:67"`, `"Final Score"`.
        /// Rendered verbatim.
        public var subtitle: String?
        /// Hex color (e.g. `"#34C759"`) applied to accents. `nil` uses the template tint.
        public var statusColor: String?
        /// Message shown when the activity becomes stale.
        public var staleMessage: String?

        public init(
            homeScore: Int? = nil,
            awayScore: Int? = nil,
            subtitle: String? = nil,
            statusColor: String? = nil,
            staleMessage: String? = nil
        ) {
            self.homeScore = homeScore
            self.awayScore = awayScore
            self.subtitle = subtitle
            self.statusColor = statusColor
            self.staleMessage = staleMessage
        }
    }
}
#endif
