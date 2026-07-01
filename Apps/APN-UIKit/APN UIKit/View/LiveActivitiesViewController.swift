@unsafe @preconcurrency import ActivityKit
import CioLiveActivities
import CioLiveActivities_Attributes
import CioLiveActivities_Templates
import UIKit

@available(iOS 17.2, *)
class LiveActivitiesViewController: BaseViewController {
    // MARK: - Active activities

    // Handles returned by the SDK's `start`, so update/end route through Customer.io
    // (and emit the local `Live Notification Event`s). A backend push that ends/updates
    // an activity is applied by the OS and is never reported.
    private var liveScoreActivity: CIOLiveActivity<CIOLiveScoreAttributes>?
    private var deliveryActivity: CIOLiveActivity<CIODeliveryTrackingAttributes>?
    private var countdownActivity: CIOLiveActivity<CIOCountdownTimerAttributes>?
    private var flightActivity: CIOLiveActivity<CIOFlightStatusAttributes>?
    private var auctionActivity: CIOLiveActivity<CIOAuctionBidAttributes>?

    // MARK: - Buttons

    private weak var liveScoreButton: ThemeButton?
    private weak var deliveryButton: ThemeButton?
    private weak var countdownButton: ThemeButton?
    private weak var flightButton: ThemeButton?
    private weak var auctionButton: ThemeButton?

    private let demoBranding = CIOActivityBranding(name: "Next Level Sports", logoKey: "NL-Logo", accentColor: "#F26726")

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

        let liveScoreBtn = makeButton(title: "Start Live Score", action: #selector(toggleLiveScore))
        liveScoreButton = liveScoreBtn
        stack.addArrangedSubview(makeCard(
            title: "Live Score",
            description: "Scoreboard with team scores, period, and clock.",
            buttons: [liveScoreBtn, makeButton(title: "Update Live Score", action: #selector(updateLiveScore))]
        ))

        let deliveryBtn = makeButton(title: "Start Delivery Tracking", action: #selector(toggleDelivery))
        deliveryButton = deliveryBtn
        stack.addArrangedSubview(makeCard(
            title: "Delivery Tracking",
            description: "Step-based order progress with ETA countdown.",
            buttons: [deliveryBtn, makeButton(title: "Update Delivery Tracking", action: #selector(updateDelivery))]
        ))

        let countdownBtn = makeButton(title: "Start Countdown Timer", action: #selector(toggleCountdown))
        countdownButton = countdownBtn
        stack.addArrangedSubview(makeCard(
            title: "Countdown Timer",
            description: "Countdown to a target date with configurable messaging.",
            buttons: [countdownBtn, makeButton(title: "Update Countdown Timer", action: #selector(updateCountdown))]
        ))

        let flightBtn = makeButton(title: "Start Flight Status", action: #selector(toggleFlight))
        flightButton = flightBtn
        stack.addArrangedSubview(makeCard(
            title: "Flight Status",
            description: "Real-time flight tracking with gate and in-flight progress.",
            buttons: [flightBtn, makeButton(title: "Update Flight Status", action: #selector(updateFlight))]
        ))

        let auctionBtn = makeButton(title: "Start Auction Bid", action: #selector(toggleAuction))
        auctionButton = auctionBtn
        stack.addArrangedSubview(makeCard(
            title: "Auction Bid",
            description: "Live auction with current bid, bid count, and countdown.",
            buttons: [auctionBtn, makeButton(title: "Update Auction Bid", action: #selector(updateAuction))]
        ))
    }

    private func makeCard(title: String, description: String, buttons: [ThemeButton]) -> UIView {
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
        return card
    }

    private func makeButton(title: String, action: Selector) -> ThemeButton {
        let button = ThemeButton()
        button.setTitle(title, for: .normal)
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    // MARK: - Update actions (send a mock content-state update → emits an `update` event)

    @objc private func updateLiveScore() {
        guard let handle = liveScoreActivity else {
            showToast(withMessage: "Start Live Score first")
            return
        }
        Task { @MainActor in
            await handle.update(.init(homeScore: Int.random(in: 0 ... 5), awayScore: Int.random(in: 0 ... 5), period: "2nd"))
        }
    }

    @objc private func updateDelivery() {
        guard let handle = deliveryActivity else {
            showToast(withMessage: "Start Delivery Tracking first")
            return
        }
        Task { @MainActor in
            await handle.update(.init(
                statusMessage: "Nearby",
                stepCurrent: 3,
                stepTotal: 4,
                estimatedArrival: Date().addingTimeInterval(600)
            ))
        }
    }

    @objc private func updateCountdown() {
        guard let handle = countdownActivity else {
            showToast(withMessage: "Start Countdown Timer first")
            return
        }
        Task { @MainActor in
            await handle.update(.init(
                targetDate: Date().addingTimeInterval(1800),
                statusMessage: "Almost there",
                expiredMessage: "Sale is live!"
            ))
        }
    }

    @objc private func updateFlight() {
        guard let handle = flightActivity else {
            showToast(withMessage: "Start Flight Status first")
            return
        }
        Task { @MainActor in
            await handle.update(.init(
                statusMessage: "Boarding",
                gate: "B14",
                terminal: "2",
                scheduledDeparture: Date().addingTimeInterval(900),
                estimatedArrival: Date().addingTimeInterval(21600)
            ))
        }
    }

    @objc private func updateAuction() {
        guard let handle = auctionActivity else {
            showToast(withMessage: "Start Auction Bid first")
            return
        }
        Task { @MainActor in
            await handle.update(.init(
                currentBid: "150.00",
                bidCount: 8,
                endTime: Date().addingTimeInterval(1800),
                statusMessage: "New high bid"
            ))
        }
    }

    // MARK: - Toggle actions

    @objc private func toggleLiveScore() {
        if let handle = liveScoreActivity {
            Task { @MainActor in
                await handle.end(.init(homeScore: 2, awayScore: 1, period: "Final"))
                self.liveScoreActivity = nil
                self.liveScoreButton?.setTitle("Start Live Score", for: .normal)
            }
        } else {
            do {
                liveScoreActivity = try AppDelegate.liveActivities?.start(
                    contentState: .init(homeScore: 0, awayScore: 0, period: "1st")
                ) { activityInstanceId in
                    CIOLiveScoreAttributes(
                        activityInstanceId: activityInstanceId,
                        homeTeam: .init(name: "HME"),
                        awayTeam: .init(name: "AWY"),
                        sport: "Demo"
                    )
                }
                liveScoreButton?.setTitle("End Live Score", for: .normal)
            } catch {
                NSLog("[LiveActivities] Failed to start Live Score: \(error)")
                showToast(withMessage: "Failed to start Live Score: \(error.localizedDescription)")
            }
        }
    }

    @objc private func toggleDelivery() {
        if let handle = deliveryActivity {
            Task { @MainActor in
                await handle.end(.init(
                    statusMessage: "Delivered",
                    stepCurrent: 4,
                    stepTotal: 4,
                    estimatedArrival: Date()
                ))
                self.deliveryActivity = nil
                self.deliveryButton?.setTitle("Start Delivery Tracking", for: .normal)
            }
        } else {
            do {
                deliveryActivity = try AppDelegate.liveActivities?.start(
                    contentState: .init(
                        statusMessage: "Out for delivery",
                        stepCurrent: 2,
                        stepTotal: 4,
                        estimatedArrival: Date().addingTimeInterval(3600)
                    )
                ) { activityInstanceId in
                    CIODeliveryTrackingAttributes(
                        activityInstanceId: activityInstanceId,
                        branding: self.demoBranding,
                        orderId: "ORD-001"
                    )
                }
                deliveryButton?.setTitle("End Delivery Tracking", for: .normal)
            } catch {
                NSLog("[LiveActivities] Failed to start Delivery Tracking: \(error)")
                showToast(withMessage: "Failed to start Delivery Tracking: \(error.localizedDescription)")
            }
        }
    }

    @objc private func toggleCountdown() {
        if let handle = countdownActivity {
            Task { @MainActor in
                await handle.end(.init(
                    targetDate: Date(),
                    statusMessage: "Sale ended",
                    expiredMessage: "Sale is live!"
                ))
                self.countdownActivity = nil
                self.countdownButton?.setTitle("Start Countdown Timer", for: .normal)
            }
        } else {
            do {
                countdownActivity = try AppDelegate.liveActivities?.start(
                    contentState: .init(
                        targetDate: Date().addingTimeInterval(3600),
                        statusMessage: "Sale ends in",
                        expiredMessage: "Sale is live!"
                    )
                ) { activityInstanceId in
                    CIOCountdownTimerAttributes(
                        activityInstanceId: activityInstanceId,
                        branding: self.demoBranding,
                        title: "Flash Sale"
                    )
                }
                countdownButton?.setTitle("End Countdown Timer", for: .normal)
            } catch {
                NSLog("[LiveActivities] Failed to start Countdown Timer: \(error)")
                showToast(withMessage: "Failed to start Countdown Timer: \(error.localizedDescription)")
            }
        }
    }

    @objc private func toggleFlight() {
        if let handle = flightActivity {
            Task { @MainActor in
                await handle.end(.init(
                    statusMessage: "Landed",
                    gate: "B12",
                    terminal: "2",
                    scheduledDeparture: Date(),
                    estimatedArrival: Date()
                ))
                self.flightActivity = nil
                self.flightButton?.setTitle("Start Flight Status", for: .normal)
            }
        } else {
            do {
                let now = Date()
                flightActivity = try AppDelegate.liveActivities?.start(
                    contentState: .init(
                        statusMessage: "On Time",
                        gate: "B12",
                        terminal: "2",
                        scheduledDeparture: now.addingTimeInterval(1800),
                        estimatedArrival: now.addingTimeInterval(21600)
                    )
                ) { activityInstanceId in
                    CIOFlightStatusAttributes(
                        activityInstanceId: activityInstanceId,
                        branding: self.demoBranding,
                        flightNumber: "CIO101",
                        origin: .init(code: "SFO", city: "San Francisco"),
                        destination: .init(code: "JFK", city: "New York")
                    )
                }
                flightButton?.setTitle("End Flight Status", for: .normal)
            } catch {
                NSLog("[LiveActivities] Failed to start Flight Status: \(error)")
                showToast(withMessage: "Failed to start Flight Status: \(error.localizedDescription)")
            }
        }
    }

    @objc private func toggleAuction() {
        if let handle = auctionActivity {
            Task { @MainActor in
                await handle.end(.init(
                    currentBid: "250.00",
                    bidCount: 12,
                    endTime: Date(),
                    statusMessage: "Auction ended"
                ))
                self.auctionActivity = nil
                self.auctionButton?.setTitle("Start Auction Bid", for: .normal)
            }
        } else {
            do {
                auctionActivity = try AppDelegate.liveActivities?.start(
                    contentState: .init(
                        currentBid: "100.00",
                        bidCount: 5,
                        endTime: Date().addingTimeInterval(3600),
                        statusMessage: "You've been outbid"
                    )
                ) { activityInstanceId in
                    CIOAuctionBidAttributes(
                        activityInstanceId: activityInstanceId,
                        branding: self.demoBranding,
                        itemTitle: "Vintage Watch"
                    )
                }
                auctionButton?.setTitle("End Auction Bid", for: .normal)
            } catch {
                NSLog("[LiveActivities] Failed to start Auction Bid: \(error)")
                showToast(withMessage: "Failed to start Auction Bid: \(error.localizedDescription)")
            }
        }
    }
}
