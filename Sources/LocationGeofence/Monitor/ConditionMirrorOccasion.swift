/// Which occasion produced a `condition_mirror` record, so a reader can tell a sync's own
/// post-registration check from a sample taken while nothing was happening. Absent it, a clean
/// record during a silent window is indistinguishable from one emitted by a sync that had just run.
enum ConditionMirrorOccasion {
    case sync
    case poll

    /// Literals rather than a `String` raw value: a case rename then cannot silently change the
    /// emitted token, and the raw-value spelling is unwritable here anyway — SwiftFormat and
    /// SwiftLint both strip `case sync = "sync"`.
    var token: String {
        switch self {
        case .sync: return "sync"
        case .poll: return "poll"
        }
    }
}
