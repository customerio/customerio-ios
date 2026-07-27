@unsafe @preconcurrency import ActivityKit
import CioDataPipelines
import CioLiveActivities
import CioLiveActivities_Attributes
import CioLiveActivities_Templates
import Foundation
import UIKit

// Demo screen exercising the app's delivery-tracking Live Activity via the SDK's local API,
// plus the adopt / unregistered-type / debug paths.
// Length rules are relaxed here since it intentionally wires up several independent controls.
// swiftlint:disable file_length

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
final class LiveActivityDemoDriver<A: ActivityAttributes>: LiveActivityDemoDriving where A.ContentState: Sendable {
    let title: String
    private let module: () -> LiveActivitiesInstance
    private let attributes: A
    private let phases: [A.ContentState]
    private let endState: A.ContentState
    private let log: (String) -> Void
    private let autoStepDelay: TimeInterval = 5

    private var handle: CIOLiveActivity<A>?
    private var phaseIndex = 0
    private var autoTask: Task<Void, Never>?

    var onChange: (() -> Void)?
    var isActive: Bool { handle != nil }

    init(
        title: String,
        module: @escaping () -> LiveActivitiesInstance,
        attributes: A,
        phases: [A.ContentState],
        endState: A.ContentState,
        log: @escaping (String) -> Void
    ) {
        self.title = title
        self.module = module
        self.attributes = attributes
        self.phases = phases
        self.endState = endState
        self.log = log
    }

    func toggle() {
        if isActive { end() } else { start() }
    }

    private func start() {
        do {
            guard let started = try module().start(attributes, contentState: phases[0]) else {
                // nil = module not initialized or this type wasn't registered (both are logged by
                // the SDK). A genuine ActivityKit failure would throw and land in `catch` below.
                log("\(title): not started (module not initialized or type not registered)")
                return
            }
            handle = started
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
        autoTask?.cancel()
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
private extension CIOLiveActivity where Attributes.ContentState: Sendable {
    /// Fire-and-forget end used by the driver's synchronous `end()`.
    @MainActor
    func endDetached(_ finalContentState: Attributes.ContentState) {
        Task { @MainActor in await self.end(finalContentState) }
    }
}

// MARK: - View controller

@available(iOS 17.2, *)
class LiveActivitiesViewController: BaseViewController {
    /// App-scheme deep link that routes to this screen (used as the demo activities' tap target,
    /// and matched by `SceneDelegate` to push this screen + let the SDK track `opened`).
    static let deepLink = "apn-uikit://live-activities"
    /// Host component of `deepLink`, matched by `SceneDelegate` for routing.
    static let deepLinkHost = "live-activities"

    private var drivers: [any LiveActivityDemoDriving] = []

    // Adopt demo: an activity the app creates itself, then hands to the SDK via `adopt`.
    private var adoptHandle: CIOLiveActivity<DeliveryActivityAttributes>?
    private weak var adoptButton: ThemeButton?

    private let logView = UITextView()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Live Activities"
        view.backgroundColor = .systemBackground
        buildUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = false
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

    // Builds the delivery-tracking driver with a realistic multi-phase sequence: order placed →
    // preparing → out for delivery (green tint) → delivered, each phase sending an `update`.
    private func makeDrivers() -> [(any LiveActivityDemoDriving, String)] {
        let module: () -> LiveActivitiesInstance = { CustomerIO.liveActivities }
        let log: (String) -> Void = { [weak self] line in self?.appendLog(line) }
        func future(_ seconds: TimeInterval) -> EpochSecondsDate {
            EpochSecondsDate(Date().addingTimeInterval(seconds))
        }
        // Deep link back to this Live Activities screen. Carried on EVERY content-state so the
        // activity's tap target (`widgetURL`) keeps routing here across updates — not just the
        // first. (Locally-started activities carry no delivery id, so no `opened` metric fires; a
        // real Customer.io push carries the id in the same `cioMetadata`.)
        let laDeepLink = CIOLiveActivityMetadata(deepLink: LiveActivitiesViewController.deepLink)

        let delivery = LiveActivityDemoDriver<DeliveryActivityAttributes>(
            title: "Delivery Tracking",
            module: module,
            attributes: DeliveryActivityAttributes(orderNumber: "Order #ABC-1234"),
            phases: [
                .init(title: "Order placed", subtitle: "Arriving at 1:45 PM", progress: .init(current: 1, total: 4), estimatedArrival: future(1800), cioMetadata: laDeepLink),
                .init(title: "Preparing your order…", subtitle: "Arriving at 1:45 PM", progress: .init(current: 2, total: 4), estimatedArrival: future(1500), cioMetadata: laDeepLink),
                .init(title: "Out for delivery", subtitle: "Arriving at 1:30 PM", progress: .init(current: 3, total: 4), estimatedArrival: future(600), statusColor: "#34C759", cioMetadata: laDeepLink)
            ],
            endState: .init(title: "Delivered", subtitle: "Arrived at 1:28 PM", progress: .init(current: 4, total: 4), cioMetadata: laDeepLink),
            log: log
        )

        // The SDK's built-in Segments template, styled with the "Chica" food-delivery branding
        // (orange gradient + logo), compiled into the live widget via `SegmentsDemoBranding.active`.
        let segments = LiveActivityDemoDriver<CIOSegmentsAttributes>(
            title: "Segments (Chica)",
            module: module,
            attributes: CIOSegmentsAttributes(header: "Chica"),
            phases: [
                .init(status: "Order placed", substatus: "We got your order", segmentsTotal: 4, segmentsComplete: 1, trailingText: "1/4", cioMetadata: laDeepLink),
                .init(status: "Preparing your order", substatus: "Your food is being cooked", segmentsTotal: 4, segmentsComplete: 2, trailingText: "2/4", cioMetadata: laDeepLink),
                .init(status: "Out for delivery", substatus: "Arriving soon", segmentsTotal: 4, segmentsComplete: 3, trailingText: "5 min", cioMetadata: laDeepLink)
            ],
            endState: .init(status: "Delivered", substatus: "Enjoy your meal!", segmentsTotal: 4, segmentsComplete: 4, trailingText: "Done", cioMetadata: laDeepLink),
            log: log
        )

        // The SDK's built-in Countdown Timer template (violet→magenta "sale" branding). The finished
        // phase drops `endTime`, so the live timer disappears and the done message shows.
        let countdown = LiveActivityDemoDriver<CIOCountdownTimerAttributes>(
            title: "Countdown (Sale)",
            module: module,
            attributes: CIOCountdownTimerAttributes(header: "Summer Sale"),
            phases: [
                .init(title: "Flash sale ends in", statusMessage: "Up to 50% off sitewide", endTime: future(3600), cioMetadata: laDeepLink),
                .init(title: "Almost gone!", statusMessage: "Final hour", endTime: future(600), cioMetadata: laDeepLink)
            ],
            endState: .init(title: "Sale ended", statusMessage: "Thanks for shopping", cioMetadata: laDeepLink),
            log: log
        )

        return [
            (delivery, "Step progress + live ETA countdown; the out-for-delivery phase tints green (statusColor)."),
            (segments, "SDK-provided Segments template with the Chica food-delivery branding (orange gradient + logo)."),
            (countdown, "SDK-provided Countdown Timer template — a live countdown to endTime; ending the activity drops the timer and shows the finished message.")
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
        let unknownButton = makeButton("Start unregistered type (returns nil)")
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
            description: "Trigger the unregistered-type path (start returns nil) + local start/update/end. (Push tokens aren't publicly readable — they go to Customer.io / os_log.)",
            buttons: [unknownButton, clearButton],
            extraViews: [logView]
        )
    }

    // MARK: - Adopt handlers

    private func toggleAdopt() {
        if let handle = adoptHandle {
            Task { @MainActor in
                await handle.end(.init(title: "Delivered", subtitle: "Adopted — ended", progress: .init(current: 4, total: 4)))
                self.adoptHandle = nil
                self.adoptButton?.setTitle("Start (app-created) & Adopt", for: .normal)
                self.appendLog("Adopt: ended")
            }
            return
        }
        do {
            let attributes = DeliveryActivityAttributes(orderNumber: "Order #ADOPT-1")
            let state = DeliveryActivityAttributes.ContentState(
                title: "Adopted (app-created)",
                subtitle: "Order placed",
                progress: .init(current: 1, total: 4),
                estimatedArrival: EpochSecondsDate(Date().addingTimeInterval(1800))
            )
            let content = ActivityContent(state: state, staleDate: nil)
            let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            guard let adopted = CustomerIO.liveActivities.adopt(activity) else {
                // adopt returned nil = module not initialized: don't leave the just-created system
                // activity orphaned, and don't flip the UI to "End Adopted" with no handle to end.
                appendLog("Adopt: SDK not initialized — ending orphaned activity")
                showToast(withMessage: "SDK not initialized")
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
                return
            }
            adoptHandle = adopted
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
            await handle.update(.init(title: "Out for delivery", subtitle: "Adopted — updated", progress: .init(current: 3, total: 4), estimatedArrival: EpochSecondsDate(Date().addingTimeInterval(600))))
            self.appendLog("Adopt: updated")
        }
    }

    // MARK: - Error path

    /// A plain `ActivityAttributes` type (no `CIOActivityAttribute` conformance) that is never
    /// passed to `LiveActivityConfigBuilder.register`, so `start` returns `nil` (logging the
    /// unregistered type) before requesting anything — the iOS analog of Android's "unknown
    /// template" path. Also demonstrates that custom rendering needs no CIO protocol on the attributes.
    @available(iOS 17.2, *)
    private struct UnregisteredDemoAttributes: ActivityAttributes {
        struct ContentState: Codable, Hashable, Sendable {}
        // Built inside the type so `ContentState` resolves to the nested struct, not the
        // `ActivityAttributes.ContentState` associatedtype existential.
        static let sampleState = ContentState()
    }

    private func triggerUnknownType() {
        do {
            if try CustomerIO.liveActivities.start(
                UnregisteredDemoAttributes(),
                contentState: UnregisteredDemoAttributes.sampleState
            ) != nil {
                appendLog("Unknown type: unexpectedly started")
            } else {
                // Expected: an unregistered type returns nil (the SDK logs the reason) rather than
                // starting or throwing. A nil here also covers the "module not initialized" case.
                appendLog("Unknown type: not started — returned nil (expected)")
                showToast(withMessage: "Expected: unregistered type not started")
            }
        } catch {
            // Only a genuine ActivityKit failure throws here; the unregistered case returns nil above.
            appendLog("Unknown type: threw — \(error)")
            showToast(withMessage: "Unexpected error: \(error)")
        }
    }

    // MARK: - Log

    private func appendLog(_ line: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let entry = "\(formatter.string(from: Date()))  \(line)\n"
        logView.text = entry + logView.text
    }
}

// MARK: - View builders

// Extracted into an extension so the main type body stays under SwiftLint's
// type_body_length limit (sample-only UI scaffolding).
@available(iOS 17.2, *)
private extension LiveActivitiesViewController {
    func makeCard(title: String, description: String, buttons: [ThemeButton], extraViews: [UIView] = []) -> UIView {
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

    func makeButton(_ title: String) -> ThemeButton {
        let button = ThemeButton()
        button.setTitle(title, for: .normal)
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        return button
    }
}

// swiftlint:enable file_length
