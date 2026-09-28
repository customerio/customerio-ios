/// Which occasion produced a `condition_mirror` record: a sync's own post-registration check or a
/// timed sample.
enum ConditionMirrorOccasion {
    case sync
    case poll

    /// Literals rather than a `String` raw value: a case rename cannot change the emitted token,
    /// and SwiftFormat/SwiftLint strip `case sync = "sync"` anyway.
    var token: String {
        switch self {
        case .sync: return "sync"
        case .poll: return "poll"
        }
    }
}
