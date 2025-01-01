/// Enum to define how CustomerIO SDK should handle screen view events.
public enum ScreenView: String {
    /// Screen view events are sent to destinations for analytics purposes.
    /// They are also used to display in-app messages based on page rules.
    case all

    /// Screen view events are kept on device only. They are used to display in-app messages based on
    /// page rules. Events are not sent to our back end servers.
    case inApp = "inapp"

    /// Returns the ScreenView enum case for the given name.
    /// Returns fallback if the specified enum type has no constant with the given name.
    /// Defaults to .all
    public static func getScreenView(_ screenView: String?, fallback: ScreenView = .all) -> ScreenView {
        guard let screenView = screenView,
              !screenView.isEmpty,
              let value = ScreenView(rawValue: screenView.lowercased())
        else {
            return fallback
        }
        return value
    }
}
