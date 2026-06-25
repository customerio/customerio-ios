import CioLiveActivities_Attributes

#if os(iOS)
import ActivityKit

/// Attributes for the Live Score template.
///
/// Tracks a two-team match in any sport with real-time score, period, and clock updates.
@available(iOS 17.2, *)
public struct CIOLiveScoreAttributes: CIOActivityAttribute {

    public static let identifier = "io.customer.liveactivities.livescore"

    // MARK: - Nested types

    public struct Team: Codable, Hashable, Sendable {
        /// Display name for the team.
        public var name: String
        /// AssetKey for the team logo, resolved via `CIOAssetLibrary`.
        public var logoKey: String?

        public init(name: String, logoKey: String? = nil) {
            self.name = name
            self.logoKey = logoKey
        }
    }

    // MARK: - Static attributes

    public var activityInstanceId: String
    public var homeTeam: Team
    public var awayTeam: Team
    /// Sport identifier used for layout hints (e.g. `"soccer"`, `"basketball"`).
    public var sport: String
    /// AssetKey for the league or competition logo.
    public var leagueLogoKey: String?

    public init(
        activityInstanceId: String,
        homeTeam: Team,
        awayTeam: Team,
        sport: String,
        leagueLogoKey: String? = nil
    ) {
        self.activityInstanceId = activityInstanceId
        self.homeTeam = homeTeam
        self.awayTeam = awayTeam
        self.sport = sport
        self.leagueLogoKey = leagueLogoKey
    }

    // MARK: - Dynamic content state

    public struct ContentState: Codable, Hashable, Sendable {
        public var homeScore: Int
        public var awayScore: Int
        /// Period label e.g. `"2nd Quarter"`, `"HT"`, `"FT"`.
        public var period: String
        /// Game clock string e.g. `"14:32"`. `nil` when not applicable.
        public var clock: String?
        /// Override label for special situations e.g. `"Penalty Shootout"`.
        public var statusMessage: String?
        /// Message shown when the activity becomes stale.
        public var staleMessage: String?

        public init(
            homeScore: Int,
            awayScore: Int,
            period: String,
            clock: String? = nil,
            statusMessage: String? = nil,
            staleMessage: String? = nil
        ) {
            self.homeScore = homeScore
            self.awayScore = awayScore
            self.period = period
            self.clock = clock
            self.statusMessage = statusMessage
            self.staleMessage = staleMessage
        }
    }
}
#endif
