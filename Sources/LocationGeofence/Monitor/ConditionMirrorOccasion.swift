enum ConditionMirrorOccasion {
    case sync
    case poll

    /// Literals, not a raw value: SwiftFormat/SwiftLint strip `case sync = "sync"`.
    var token: String {
        switch self {
        case .sync: return "sync"
        case .poll: return "poll"
        }
    }
}
