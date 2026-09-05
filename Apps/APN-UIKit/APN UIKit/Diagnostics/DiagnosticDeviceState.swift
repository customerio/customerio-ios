import Darwin
import Foundation
import Network
import UIKit

/// The `dev` block attached to every record.
final class DiagnosticDeviceState: NSObject, @unchecked Sendable {
    private struct Snapshot: Equatable {
        /// `nil` until UIKit has populated it; never the raw -1 sentinel.
        var battery: Float?
        var charging = false
        var lowPower = false
        var thermal = "unknown"
        var network = "unknown"
        var foreground = false
        var backgroundRefresh = "unknown"
    }

    private let lock = NSLock()
    private var snapshot = Snapshot()
    private var onChange: (@Sendable (String) -> Void)?

    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "io.customer.diagnostics.path")

    // MARK: - Lifecycle

    /// - Parameter onChange: invoked with a short reason whenever a value changes, so the sink can
    ///   write a `device.state` record. The new values ride along in the `dev` block of that
    ///   record like they do on every other record. `@Sendable` because thermal, power and network
    ///   changes are all delivered off the main thread.
    @MainActor
    func start(onChange: @escaping @Sendable (String) -> Void) {
        lock.lock()
        self.onChange = onChange
        lock.unlock()

        UIDevice.current.isBatteryMonitoringEnabled = true
        readAll()

        let center = NotificationCenter.default
        // Both families, deliberately. This app is scene-based — it declares a
        // `UIApplicationSceneManifest` and a `SceneDelegate` — and iOS does not post the
        // `UIApplication` lifecycle notifications to a scene-based app, only the `UIScene` ones.
        // Observing only the former leaves `fg` stuck at its launch value for the whole drive.
        // The `UIApplication` names are kept because a background launch has no scene at all.
        for name: NSNotification.Name in [
            UIApplication.didBecomeActiveNotification,
            UIApplication.willResignActiveNotification,
            UIApplication.didEnterBackgroundNotification,
            UIApplication.willEnterForegroundNotification,
            UIScene.didActivateNotification,
            UIScene.willDeactivateNotification,
            UIScene.didEnterBackgroundNotification,
            UIScene.willEnterForegroundNotification
        ] {
            center.addObserver(self, selector: #selector(appLifecycleChanged), name: name, object: nil)
        }
        center.addObserver(
            self,
            selector: #selector(backgroundRefreshChanged),
            name: UIApplication.backgroundRefreshStatusDidChangeNotification,
            object: nil
        )
        for name: NSNotification.Name in [
            UIDevice.batteryLevelDidChangeNotification,
            UIDevice.batteryStateDidChangeNotification
        ] {
            center.addObserver(self, selector: #selector(batteryChanged), name: name, object: nil)
        }
        center.addObserver(
            self,
            selector: #selector(powerStateChanged),
            name: NSNotification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )

        startPathMonitor()
    }

    /// `nonisolated` for the same reason the sink's dispatcher is: the handler runs on
    /// `pathQueue`, and a closure formed inside the `@MainActor` `start()` above would inherit
    /// main-actor isolation and trap the first time the network path changes.
    private nonisolated func startPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            self?.update("net") { $0.network = DiagnosticDeviceState.describe(path) }
        }
        pathMonitor.start(queue: pathQueue)
    }

    // MARK: - Reading

    /// Safe to call from any thread. Reads only the cached struct, never UIKit — every
    /// main-actor-only value is captured on the main thread by the observers below and stored
    /// here, because SDK log records arrive on whatever thread the SDK happened to be using.
    func snapshotJSON() -> String {
        lock.lock()
        let current = snapshot
        lock.unlock()

        var out = "{"
        out += "\"batt\":\(current.battery.map { String(format: "%.2f", $0) } ?? "null")"
        out += ",\"charging\":\(current.charging)"
        out += ",\"lowPower\":\(current.lowPower)"
        out += ",\"thermal\":\(DiagnosticJSON.string(current.thermal))"
        out += ",\"net\":\(DiagnosticJSON.string(current.network))"
        out += ",\"fg\":\(current.foreground)"
        out += ",\"bgRefresh\":\(DiagnosticJSON.string(current.backgroundRefresh))"
        out += "}"
        return out
    }

    // MARK: - Observers

    @MainActor @objc private func appLifecycleChanged() {
        update("fg") { $0.foreground = UIApplication.shared.applicationState != .background }
    }

    @MainActor @objc private func backgroundRefreshChanged() {
        update("bgRefresh") {
            $0.backgroundRefresh = DiagnosticDeviceState.describe(UIApplication.shared.backgroundRefreshStatus)
        }
    }

    /// `-1` is UIKit's "not known yet" sentinel, not a level.
    @MainActor
    private static func batteryLevel(_ device: UIDevice) -> Float? {
        let level = device.batteryLevel
        return level >= 0 ? level : nil
    }

    @MainActor @objc private func batteryChanged() {
        update("batt") {
            $0.battery = DiagnosticDeviceState.batteryLevel(UIDevice.current)
            $0.charging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
        }
    }

    @objc private func powerStateChanged() {
        update("lowPower") { $0.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
    }

    @objc private func thermalStateChanged() {
        update("thermal") { $0.thermal = DiagnosticDeviceState.describe(ProcessInfo.processInfo.thermalState) }
    }

    @MainActor
    private func readAll() {
        let application = UIApplication.shared
        let device = UIDevice.current
        let process = ProcessInfo.processInfo

        lock.lock()
        // UIKit populates batteryLevel asynchronously after monitoring is enabled and reports -1
        // meanwhile, correcting only on a 1% step — which never arrives during a short background
        // wake. Absent is honest; -1.00 reads as a real measurement.
        snapshot.battery = DiagnosticDeviceState.batteryLevel(device)
        snapshot.charging = device.batteryState == .charging || device.batteryState == .full
        snapshot.lowPower = process.isLowPowerModeEnabled
        snapshot.thermal = DiagnosticDeviceState.describe(process.thermalState)
        snapshot.foreground = application.applicationState != .background
        snapshot.backgroundRefresh = DiagnosticDeviceState.describe(application.backgroundRefreshStatus)
        lock.unlock()
    }

    /// Writes a `device.state` record only when a value actually moved. Several notifications
    /// describe the same transition — a scene deactivating and the app backgrounding arrive
    /// together — and recording each one would fill the file with rows that say nothing changed.
    private func update(_ reason: String, _ mutate: (inout Snapshot) -> Void) {
        lock.lock()
        let before = snapshot
        mutate(&snapshot)
        let changed = snapshot != before
        let callback = onChange
        lock.unlock()
        guard changed else { return }
        callback?(reason)
    }

    // MARK: - Descriptions

    private static func describe(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    private static func describe(_ status: UIBackgroundRefreshStatus) -> String {
        switch status {
        case .available: return "available"
        case .denied: return "denied"
        case .restricted: return "restricted"
        @unknown default: return "unknown"
        }
    }

    private static func describe(_ path: NWPath) -> String {
        guard path.status == .satisfied else { return "none" }
        if path.usesInterfaceType(.wifi) { return "wifi" }
        if path.usesInterfaceType(.cellular) { return "cellular" }
        if path.usesInterfaceType(.wiredEthernet) { return "wired" }
        return "other"
    }

    /// Hardware identifier such as `iPhone16,1`. On a simulator `hw.machine` reports the host
    /// architecture, so the simulated model is read from the environment instead — otherwise every
    /// simulator session in a corpus claims to be an `arm64`.
    static func hardwareModel() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulated) (simulator)"
        }
        var size = 0
        guard sysctlbyname("hw.machine", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var machine = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("hw.machine", &machine, &size, nil, 0) == 0 else { return "unknown" }
        return String(bytes: machine.prefix { $0 != 0 }, encoding: .utf8) ?? "unknown"
    }
}
