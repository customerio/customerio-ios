@unsafe @preconcurrency import ActivityKit
import CioLiveActivities
import CioLiveActivities_Attributes
import CioLiveActivities_Templates
import Foundation
import UIKit

// Demo screen exercising all five Live Activity templates plus adopt / error / debug paths.
// Length rules are relaxed here since it intentionally wires up many independent controls.
// swiftlint:disable file_length type_body_length

// MARK: - Phase driver

/// Type-erased interface so the view controller can hold heterogeneous per-template drivers.
@available(iOS 17.2, *)
@MainActor
protocol LiveActivityDemoDriving: AnyObject {
    var title: String { get }
    var isActive: Bool { get }
    var onChange: (() -> Void)? { get set }
    /// Start if idle, end (with the final content state) if active.
    func toggle()
    /// Advance to the next phase (sends an `update`).
    func advance()
    /// Start, step through every phase on a timer, then end — hands-free.
    func autoRun()
}

/// Drives one template through an ordered list of realistic phases via the SDK's local API.
/// `phases[0]` is the start content; each subsequent phase is an `update`; `endState` is the
/// final content sent on `end`. This mirrors the Android demo's step arrays.
@available(iOS 17.2, *)
@MainActor
final class LiveActivityDemoDriver<A: CIOActivityAttribute>: LiveActivityDemoDriving where A.ContentState: Sendable {
    let title: String
    private let module: () -> LiveActivitiesModule?
    private let makeAttributes: (String) -> A
    private let phases: [A.ContentState]
    private let endState: A.ContentState
    private let log: (String) -> Void
    private let autoStepDelay: TimeInterval = 3

    private var handle: CIOLiveActivity<A>?
    private var phaseIndex = 0
    private var autoTask: Task<Void, Never>?

    var onChange: (() -> Void)?
    var isActive: Bool { handle != nil }

    init(
        title: String,
        module: @escaping () -> LiveActivitiesModule?,
        phases: [A.ContentState],
        endState: A.ContentState,
        log: @escaping (String) -> Void,
        makeAttributes: @escaping (String) -> A
    ) {
        self.title = title
        self.module = module
        self.phases = phases
        self.endState = endState
        self.log = log
        self.makeAttributes = makeAttributes
    }

    func toggle() {
        if isActive { end() } else { start() }
    }

    private func start() {
        guard let module = module() else {
            log("\(title): SDK not initialized")
            return
        }
        do {
            handle = try module.start(contentState: phases[0], attributes: makeAttributes)
            phaseIndex = 0
            log("\(title): start — phase 1/\(phases.count)")
            onChange?()
        } catch {
            log("\(title): start failed — \(error)")
        }
    }

    func advance() {
        guard let handle else {
            log("\(title): start it first")
            return
        }
        guard phaseIndex < phases.count - 1 else {
            log("\(title): already at last phase (\(phases.count)/\(phases.count))")
            return
        }
        phaseIndex += 1
        let state = phases[phaseIndex]
        let step = phaseIndex + 1
        let total = phases.count
        let name = title
        let record = log
        Task { @MainActor in
            await handle.update(state)
            record("\(name): update — phase \(step)/\(total)")
        }
    }

    private func end() {
        autoTask?.cancel()
        autoTask = nil
        guard let handle else { return }
        // Reset state up front so a second tap is a no-op (the button flips back to "Start").
        self.handle = nil
        phaseIndex = 0
        handle.endDetached(endState) // fire-and-forget via the async helper below
        log("\(title): end")
        onChange?()
    }

    func autoRun() {
        guard !isActive else {
            log("\(title): already running")
            return
        }
        start()
        guard handle != nil else { return }
        let total = phases.count
        let name = title
        let record = log
        let delay = autoStepDelay
        autoTask = Task { @MainActor [weak self] in
            for index in 1 ..< total {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1000000000))
                guard !Task.isCancelled, let self, let handle = self.handle else { return }
                await handle.update(self.phases[index])
                self.phaseIndex = index
                record("\(name): auto — phase \(index + 1)/\(total)")
            }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1000000000))
            guard !Task.isCancelled, let self else { return }
            self.end()
        }
    }
}

@available(iOS 17.2, *)
private extension CIOLiveActivity {
    /// Fire-and-forget end used by the driver's synchronous `end()`.
    @MainActor
    func endDetached(_ finalContentState: Attributes.ContentState) {
        Task { @MainActor in await self.end(finalContentState) }
    }
}

// MARK: - View controller

@available(iOS 17.2, *)
class LiveActivitiesViewController: BaseViewController {
    private var drivers: [any LiveActivityDemoDriving] = []

    // Adopt demo: an activity the app creates itself, then hands to the SDK via `adopt`.
    private var adoptHandle: CIOLiveActivity<CIOCountdownTimerAttributes>?
    private weak var adoptButton: ThemeButton?

    private let logView = UITextView()
    private var observeTask: Task<Void, Never>?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Live Activities"
        view.backgroundColor = .systemBackground
        buildUI()
        observeAppearedActivities()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = false
    }

    deinit { observeTask?.cancel() }

    // MARK: - observedActivities stream

    private func observeAppearedActivities() {
        observeTask = Task { @MainActor [weak self] in
            guard let stream = AppDelegate.liveActivities?.observedActivities else { return }
            for await info in stream {
                let user = info.userId.isEmpty ? "(anon)" : info.userId
                self?.appendLog("observed: \(info.activityType) · id=\(info.activityId.prefix(8))… · user=\(user)")
            }
        }
    }

    // MARK: - UI

    private func buildUI() {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)

        let content = UIView()
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.topAnchor.constraint(equalTo: scroll.topAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
            content.widthAnchor.constraint(equalTo: scroll.widthAnchor)
        ])

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])

        for (driver, description) in makeDrivers() {
            drivers.append(driver)
            stack.addArrangedSubview(makeDriverCard(driver, description: description))
        }

        stack.addArrangedSubview(makeAdoptCard())
        stack.addArrangedSubview(makeDebugCard())
    }

    // Builds one driver per template, each with a realistic multi-phase sequence including
    // edge cases: Live Score status tint, Delivery stale message, Countdown expiry, Flight
    // delay-red, Auction winning/outbid tints.
    // swiftlint:disable:next function_body_length
    private func makeDrivers() -> [(any LiveActivityDemoDriving, String)] {
        let module: () -> LiveActivitiesModule? = { AppDelegate.liveActivities }
        let log: (String) -> Void = { [weak self] line in self?.appendLog(line) }
        func future(_ seconds: TimeInterval) -> EpochMillisDate {
            EpochMillisDate(Date().addingTimeInterval(seconds))
        }

        let liveScore = LiveActivityDemoDriver<CIOLiveScoreAttributes>(
            title: "Live Score",
            module: module,
            phases: [
                .init(subtitle: "Starts in 15 Min"),
                .init(homeScore: 7, awayScore: 0, subtitle: "1st Quarter · 12:00"),
                .init(homeScore: 14, awayScore: 10, subtitle: "2nd Quarter · 05:30"),
                .init(homeScore: 21, awayScore: 21, subtitle: "4th Quarter · 00:42", statusColor: "#FFCC00")
            ],
            endState: .init(homeScore: 24, awayScore: 21, subtitle: "Final Score"),
            log: log
        ) { CIOLiveScoreAttributes(activityInstanceId: $0, homeTeam: .init(name: "LAL"), awayTeam: .init(name: "BOS")) }

        let delivery = LiveActivityDemoDriver<CIODeliveryTrackingAttributes>(
            title: "Delivery Tracking",
            module: module,
            phases: [
                .init(title: "Order placed", subtitle: "For Mahmoud", progress: .init(current: 1, total: 4)),
                .init(title: "Preparing your order", progress: .init(current: 2, total: 4), estimatedArrival: future(1800)),
                .init(title: "Out for delivery", subtitle: "Driver: Sam", progress: .init(current: 3, total: 4), estimatedArrival: future(600), statusColor: "#34C759"),
                .init(title: "Tracking paused", progress: .init(current: 3, total: 4), staleMessage: "Location may be out of date")
            ],
            endState: .init(title: "Delivered", progress: .init(current: 4, total: 4), estimatedArrival: future(0)),
            log: log
        ) { CIODeliveryTrackingAttributes(activityInstanceId: $0, header: "Order #ABC-1234") }

        let countdown = LiveActivityDemoDriver<CIOCountdownTimerAttributes>(
            title: "Countdown Timer",
            module: module,
            phases: [
                .init(targetDate: future(3600), subtitle: "Sale starts in"),
                .init(targetDate: future(60), subtitle: "Almost there"),
                .init(targetDate: future(-1), subtitle: "Sale ended", expiredMessage: "Sale is live!")
            ],
            endState: .init(targetDate: future(0), subtitle: "Sale ended", expiredMessage: "Sale is live!"),
            log: log
        ) { CIOCountdownTimerAttributes(activityInstanceId: $0, title: "Flash Sale") }

        let flight = LiveActivityDemoDriver<CIOFlightStatusAttributes>(
            title: "Flight Status",
            module: module,
            phases: [
                .init(status: "On Time", title: "Boarding soon", subtitle: "Gate B12 · Terminal 2", scheduledDeparture: future(1800), estimatedArrival: future(21600)),
                .init(status: "Boarding", title: "Boarding at gate B12", subtitle: "Gate B12 · Zone 3", scheduledDeparture: future(900), estimatedArrival: future(21600)),
                .init(status: "In Flight", title: "2h 15m until landing", subtitle: "Gate B12 · Terminal 2", scheduledDeparture: future(0), estimatedArrival: future(8100), progressFraction: 0.55),
                .init(status: "Delayed", title: "Delayed 25 min", subtitle: "Gate B12 · Terminal 2", scheduledDeparture: future(1500), estimatedArrival: future(21600), statusColor: "#CC3330")
            ],
            endState: .init(status: "Landed", title: "Arrived at JFK", subtitle: "Terminal 2 · Bag 4", scheduledDeparture: future(0), estimatedArrival: future(0)),
            log: log
        ) { CIOFlightStatusAttributes(activityInstanceId: $0, header: "CIO101", origin: .init(code: "SFO", city: "San Francisco"), destination: .init(code: "JFK", city: "New York")) }

        let auction = LiveActivityDemoDriver<CIOAuctionBidAttributes>(
            title: "Auction Bid",
            module: module,
            phases: [
                .init(currentBid: "100.00", subtitle: "5 bids", statusMessage: "You've been outbid", endTime: future(3600), statusColor: "#CC3330"),
                .init(currentBid: "150.00", subtitle: "8 bids", statusMessage: "You're winning", endTime: future(3600), statusColor: "#36AE3F"),
                .init(currentBid: "175.00", subtitle: "11 bids", statusMessage: "You've been outbid", endTime: future(1800), statusColor: "#CC3330")
            ],
            endState: .init(currentBid: "250.00", subtitle: "12 bids", statusMessage: "Auction ended", endTime: future(0)),
            log: log
        ) { CIOAuctionBidAttributes(activityInstanceId: $0, title: "Vintage Watch") }

        return [
            (liveScore, "Scoreboard; last update tints the status (statusColor)."),
            (delivery, "Step progress + ETA; phase 4 sends a staleMessage."),
            (countdown, "Countdown; last phase is post-target with an expiredMessage."),
            (flight, "Gate → in-flight progress → a delayed (red) phase."),
            (auction, "Outbid → winning → outbid, driven by statusColor (green/red).")
        ]
    }

    private func makeDriverCard(_ driver: any LiveActivityDemoDriving, description: String) -> UIView {
        let startButton = makeButton("Start \(driver.title)")
        startButton.addAction(UIAction { [weak driver] _ in driver?.toggle() }, for: .touchUpInside)
        driver.onChange = { [weak driver, weak startButton] in
            guard let driver else { return }
            startButton?.setTitle("\(driver.isActive ? "End" : "Start") \(driver.title)", for: .normal)
        }

        let updateButton = makeButton("Update (next phase)")
        updateButton.addAction(UIAction { [weak driver] _ in driver?.advance() }, for: .touchUpInside)

        let autoButton = makeButton("Auto-run all phases")
        autoButton.addAction(UIAction { [weak driver] _ in driver?.autoRun() }, for: .touchUpInside)

        return makeCard(title: driver.title, description: description, buttons: [startButton, updateButton, autoButton])
    }

    private func makeAdoptCard() -> UIView {
        let startButton = makeButton("Start (app-created) & Adopt")
        adoptButton = startButton
        startButton.addAction(UIAction { [weak self] _ in self?.toggleAdopt() }, for: .touchUpInside)

        let updateButton = makeButton("Update Adopted")
        updateButton.addAction(UIAction { [weak self] _ in self?.updateAdopt() }, for: .touchUpInside)

        return makeCard(
            title: "Adopt (escape hatch)",
            description: "The app creates the activity itself with Activity.request, then hands it to the SDK via adopt() so update/end route through Customer.io.",
            buttons: [startButton, updateButton]
        )
    }

    private func makeDebugCard() -> UIView {
        let unknownButton = makeButton("Start unregistered type (error)")
        unknownButton.addAction(UIAction { [weak self] _ in self?.triggerUnknownType() }, for: .touchUpInside)

        let clearButton = makeButton("Clear log")
        clearButton.addAction(UIAction { [weak self] _ in self?.logView.text = "" }, for: .touchUpInside)

        logView.isEditable = false
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.backgroundColor = UIColor(white: 0.06, alpha: 1.0)
        logView.textColor = UIColor(white: 0.9, alpha: 1.0)
        logView.layer.cornerRadius = 8
        logView.heightAnchor.constraint(equalToConstant: 180).isActive = true

        return makeCard(
            title: "Errors & Debug",
            description: "Trigger the typeNotRegistered error path, and watch the observedActivities stream + local start/update/end. (Push tokens aren't publicly readable — they go to Customer.io / os_log.)",
            buttons: [unknownButton, clearButton],
            extraViews: [logView]
        )
    }

    // MARK: - Adopt handlers

    private func toggleAdopt() {
        if let handle = adoptHandle {
            Task { @MainActor in
                await handle.end(.init(targetDate: EpochMillisDate(Date()), subtitle: "Adopted — ended", expiredMessage: "Done"))
                self.adoptHandle = nil
                self.adoptButton?.setTitle("Start (app-created) & Adopt", for: .normal)
                self.appendLog("Adopt: ended")
            }
            return
        }
        do {
            let attributes = CIOCountdownTimerAttributes(
                activityInstanceId: UUID().uuidString.lowercased(),
                title: "Adopted Countdown"
            )
            let state = CIOCountdownTimerAttributes.ContentState(
                targetDate: EpochMillisDate(Date().addingTimeInterval(3600)),
                subtitle: "Adopted (app-created)"
            )
            let content = ActivityContent(state: state, staleDate: nil)
            let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            adoptHandle = AppDelegate.liveActivities?.adopt(activity)
            adoptButton?.setTitle("End Adopted", for: .normal)
            appendLog("Adopt: app-created activity adopted")
        } catch {
            appendLog("Adopt: failed — \(error)")
            showToast(withMessage: "Adopt failed: \(error.localizedDescription)")
        }
    }

    private func updateAdopt() {
        guard let handle = adoptHandle else {
            showToast(withMessage: "Start & adopt first")
            return
        }
        Task { @MainActor in
            await handle.update(.init(targetDate: EpochMillisDate(Date().addingTimeInterval(60)), subtitle: "Adopted — updated"))
            self.appendLog("Adopt: updated")
        }
    }

    // MARK: - Error path

    /// A type that is never passed to `LiveActivityConfigBuilder.register`, so `start` throws
    /// `LiveActivityError.typeNotRegistered` before requesting anything — the iOS analog of
    /// Android's "unknown template" path.
    @available(iOS 17.2, *)
    private struct UnregisteredDemoAttributes: CIOActivityAttribute {
        struct ContentState: Codable, Hashable, Sendable {}
        var activityInstanceId: String
        // Built inside the type so `ContentState` resolves to the nested struct, not the
        // `ActivityAttributes.ContentState` associatedtype existential.
        static let sampleState = ContentState()
    }

    private func triggerUnknownType() {
        do {
            // Explicit closure type pins the generic `Attributes` so the content-state resolves.
            let makeAttributes: (String) -> UnregisteredDemoAttributes = { UnregisteredDemoAttributes(activityInstanceId: $0) }
            _ = try AppDelegate.liveActivities?.start(
                contentState: UnregisteredDemoAttributes.sampleState,
                attributes: makeAttributes
            )
            appendLog("Unknown type: unexpectedly started (no error thrown)")
        } catch {
            appendLog("Unknown type: threw (expected) — \(error)")
            showToast(withMessage: "Expected error: \(error)")
        }
    }

    // MARK: - Log

    private func appendLog(_ line: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let entry = "\(formatter.string(from: Date()))  \(line)\n"
        logView.text = entry + logView.text
    }

    // MARK: - View builders

    private func makeCard(title: String, description: String, buttons: [ThemeButton], extraViews: [UIView] = []) -> UIView {
        let card = UIView()
        card.backgroundColor = UIColor(white: 0.97, alpha: 1.0)
        card.layer.cornerRadius = 10
        card.layer.borderWidth = 1
        card.layer.borderColor = UIColor(white: 0.9, alpha: 1.0).cgColor

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .boldSystemFont(ofSize: 16)
        stack.addArrangedSubview(titleLabel)

        let descLabel = UILabel()
        descLabel.text = description
        descLabel.font = .systemFont(ofSize: 13)
        descLabel.textColor = .secondaryLabel
        descLabel.numberOfLines = 0
        stack.addArrangedSubview(descLabel)

        for button in buttons {
            stack.addArrangedSubview(button)
        }
        for extra in extraViews {
            stack.addArrangedSubview(extra)
        }
        return card
    }

    private func makeButton(_ title: String) -> ThemeButton {
        let button = ThemeButton()
        button.setTitle(title, for: .normal)
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return button
    }
}

// swiftlint:enable file_length type_body_length
