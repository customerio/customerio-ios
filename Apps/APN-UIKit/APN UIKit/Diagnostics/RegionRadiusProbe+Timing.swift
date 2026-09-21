import Foundation

/// Callback timing for ``RegionRadiusProbe``, which is what separates a measured crossing from an
/// artefact.
///
/// The 09-19 capture produced sixteen region callbacks and not one usable crossing, in two
/// different ways that looked identical in the log:
///
/// - **Launch replay.** iOS hands a relaunched process its stored belief for every monitored
///   region. On 09-19 four EXITs landed 63 ms after the process started, reporting a device
///   1052 m from the anchor — nobody newly exits a 25 m ring from a kilometre away.
/// - **Coalesced promotion.** Later the same day, in a process already five hours old, all four
///   rings ENTERed within 17 ms of each other at 22 m from the anchor. Not a replay, but not four
///   measurements either: the OS noticed once, on arrival, and promoted everything at once.
///
/// A real crossing is staggered — 100 m, then 75, then 50, then 25, seconds apart as the device
/// moves. `proc=` catches the first artefact and `dt=` catches the second, so both are filterable
/// from the data instead of being reconstructed afterwards by correlating process ids by hand.
extension RegionRadiusProbe {
    /// A callback this soon after process start is the OS replaying what it already believed, not
    /// something the device just did. Generous on purpose: the flag exists to quarantine suspect
    /// rows, and a real crossing in the first half-minute of a launch is not worth defending.
    static let replayWindow: TimeInterval = 30

    /// ` proc=` seconds since this process's probe started, ` dt=` seconds since the previous probe
    /// callback in this process (-1 for the first), ` replay=` whether `proc` falls inside
    /// ``replayWindow``.
    ///
    /// `replay=1` means suspect, not proven. Drop those rows before reading a radius. Then require
    /// `dt` to separate the rings: four callbacks sharing a `dt` near zero are one OS decision
    /// reported four times, and counting them as four promotions is how this probe would report a
    /// working 25 m ring that nothing ever measured.
    func timingFields() -> String {
        let now = Date()
        let sinceProcess = now.timeIntervalSince(probeStartedAt)
        let sincePrevious = lastCallbackAt.map { now.timeIntervalSince($0) } ?? -1
        lastCallbackAt = now
        return " proc=\(fmt(sinceProcess, 1)) dt=\(fmt(sincePrevious, 1))"
            + " replay=\(sinceProcess <= Self.replayWindow ? "1" : "0")"
    }
}
