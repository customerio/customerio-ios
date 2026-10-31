import CioInternalCommon
import Foundation

/// An `Info.plist` key, not an API, like geofence's `CIOGeofenceDiagnostics`: the hand-off log is off
/// unless an app turns it on, and builds nothing while off.
enum DataPipelinesDiagnostics {
    static let infoPlistKey = "CIODataPipelinesDiagnostics"

    private static let gate = LogTailGate()

    static var isEnabled: Bool { gate.isEnabled }

    /// Set by the replay suite: every line goes here instead of to the logger, whatever the plist says.
    static func setTestSink(_ sink: ((String) -> Void)?) {
        gate.setSink(sink)
    }

    static var testSink: ((String) -> Void)? { gate.sink }
}

/// `@unchecked Sendable`: the lazy value and the sink are only read under `lock`.
private final class LogTailGate: @unchecked Sendable {
    private let lock = NSLock()
    private var testSink: ((String) -> Void)?
    private lazy var fromBundle: Bool =
        (Bundle.main.object(forInfoDictionaryKey: DataPipelinesDiagnostics.infoPlistKey) as? Bool) ?? false

    var isEnabled: Bool {
        let (sink, enabled): (((String) -> Void)?, Bool) = lock.withLock { (testSink, fromBundle) }
        if sink != nil { return true }
        // Lines are debug logs: no point building one the logger drops
        return enabled && DIGraphShared.shared.logger.logLevel == .debug
    }

    var sink: ((String) -> Void)? { lock.withLock { testSink } }

    func setSink(_ sink: ((String) -> Void)?) {
        lock.withLock { testSink = sink }
    }
}

/// One line per input crossing into the SDK (`io=in`) and per call it makes into Segment (`io=out`),
/// in the machine-tail format ` || ev=… io=… key=value…`, so a device capture and a replay read the
/// same records. Keys and values are percent-encoded (`encode`); an empty value prints as `key=` and
/// an absent one (nil) is left out. A hand-off line holds only what the call carries (`LoggingSegmentGateway`): a
/// field that is absent was left for Segment to fill in. Each input gets a call id, restarting at 1
/// in every SDK instance, and the hand-offs it causes carry it, along with the instance that made
/// them (`sdk`). Logging only: nothing here changes what reaches Segment.
enum DataPipelineLogTail {
    static let delimiter = " || "

    private static let calls = Synchronized(0)

    private static let instances = Synchronized(0)

    /// The input running on this thread; a public call made from inside another is part of it.
    private static let threadKey = "io.customer.dataPipelines.handOffCall"

    /// A new SDK instance numbers its inputs from 1 again, as a new process does on a device.
    static func newProcess() {
        instances.mutating { $0 += 1 }
        calls.mutating { $0 = 0 }
    }

    /// The SDK instance started last. A hand-off line names the instance whose seam made it, so work
    /// an earlier instance left behind can be told apart.
    static var instance: Int { instances.wrappedValue }

    /// The input running on this thread, for work that hands off after an asynchronous hop.
    static var currentCall: Int? {
        guard DataPipelinesDiagnostics.isEnabled else { return nil }
        return Thread.current.threadDictionary[threadKey] as? Int
    }

    /// Logs `ev` as an input, then runs `block` as that input. An input made while another runs on
    /// the same thread is part of the outer one.
    @discardableResult
    static func input<R>(_ ev: String, _ fields: @autoclosure () -> [(String, String?)] = [], _ block: () throws -> R) rethrows -> R {
        guard DataPipelinesDiagnostics.isEnabled, currentCall == nil else { return try block() }
        let call = calls.mutating { value -> Int in
            value += 1
            return value
        }
        return try running(call) {
            emit("SDK input", ev, "in", [("call", String(call))] + fields())
            return try block()
        }
    }

    /// Logs `ev` as an input whose work isn't scoped to this thread, such as the SDK's own start.
    static func input(_ ev: String, _ fields: @autoclosure () -> [(String, String?)] = []) {
        input(ev, fields()) {}
    }

    /// Runs `block` as part of `call` on this thread, so the hand-offs it makes carry that call's id.
    @discardableResult
    static func running<R>(_ call: Int?, _ block: () throws -> R) rethrows -> R {
        guard let call else { return try block() }
        let dictionary = Thread.current.threadDictionary
        let previous = dictionary[threadKey]
        dictionary[threadKey] = call
        defer { dictionary[threadKey] = previous }
        return try block()
    }

    /// A call into Segment, logged before it is made.
    static func handOff(_ ev: String, _ fields: @autoclosure () -> [(String, String?)]) {
        guard DataPipelinesDiagnostics.isEnabled else { return }
        emit("handed off to Segment", ev, "out", [("call", currentCall.map(String.init))] + fields())
    }

    private static func emit(_ message: String, _ ev: String, _ io: String, _ fields: [(String, String?)]) {
        var line = "\(message)\(delimiter)ev=\(ev) io=\(io)"
        for (key, value) in fields {
            guard let value else { continue }
            // A key can come from the app (`p.<property>`), so it follows the value rules too
            line += " \(encode(key))=\(encode(value))"
        }
        if let sink = DataPipelinesDiagnostics.testSink {
            sink(line)
        } else {
            DIGraphShared.shared.logger.debug(line)
        }
    }

    /// The text with every UTF-8 byte of `%`, whitespace, `=`, `,`, `:`, `|` and control characters
    /// written as `%XX` (upper-case hex), and everything else as it is, the same for every key, so a
    /// reader splits on spaces and `=` and decodes back the exact value. Android writes the same.
    static func encode(_ text: String) -> String {
        var encoded = ""
        for scalar in text.unicodeScalars {
            if separators.contains(scalar) || scalar.properties.isWhitespace || scalar.properties.generalCategory == .control {
                for byte in String(scalar).utf8 {
                    encoded += String(format: "%%%02X", byte)
                }
            } else {
                encoded.unicodeScalars.append(scalar)
            }
        }
        return encoded
    }

    private static let separators: Set<Unicode.Scalar> = ["%", "=", ",", ":", "|"]
}
