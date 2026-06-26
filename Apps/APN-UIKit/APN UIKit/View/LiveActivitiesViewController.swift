@unsafe @preconcurrency import ActivityKit
import CioLiveActivities_Attributes
import CioLiveActivities_Templates
import UIKit

@available(iOS 17.2, *)
class LiveActivitiesViewController: BaseViewController {

    // MARK: - Active activities

    private var liveScoreActivity: Activity<CIOLiveScoreAttributes>?
    private var deliveryActivity: Activity<CIODeliveryTrackingAttributes>?
    private var countdownActivity: Activity<CIOCountdownTimerAttributes>?
    private var flightActivity: Activity<CIOFlightStatusAttributes>?
    private var auctionActivity: Activity<CIOAuctionBidAttributes>?

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
            content.widthAnchor.constraint(equalTo: scroll.widthAnchor),
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
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])

        let liveScoreBtn = makeButton(title: "Start Live Score", action: #selector(toggleLiveScore))
        liveScoreButton = liveScoreBtn
        stack.addArrangedSubview(makeCard(
            title: "Live Score",
            description: "Scoreboard with team scores, period, and clock.",
            button: liveScoreBtn
        ))

        let deliveryBtn = makeButton(title: "Start Delivery Tracking", action: #selector(toggleDelivery))
        deliveryButton = deliveryBtn
        stack.addArrangedSubview(makeCard(
            title: "Delivery Tracking",
            description: "Step-based order progress with ETA countdown.",
            button: deliveryBtn
        ))

        let countdownBtn = makeButton(title: "Start Countdown Timer", action: #selector(toggleCountdown))
        countdownButton = countdownBtn
        stack.addArrangedSubview(makeCard(
            title: "Countdown Timer",
            description: "Countdown to a target date with configurable messaging.",
            button: countdownBtn
        ))

        let flightBtn = makeButton(title: "Start Flight Status", action: #selector(toggleFlight))
        flightButton = flightBtn
        stack.addArrangedSubview(makeCard(
            title: "Flight Status",
            description: "Real-time flight tracking with gate and in-flight progress.",
            button: flightBtn
        ))

        let auctionBtn = makeButton(title: "Start Auction Bid", action: #selector(toggleAuction))
        auctionButton = auctionBtn
        stack.addArrangedSubview(makeCard(
            title: "Auction Bid",
            description: "Live auction with current bid, bid count, and countdown.",
            button: auctionBtn
        ))
    }

    private func makeCard(title: String, description: String, button: ThemeButton) -> UIView {
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
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
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

        stack.addArrangedSubview(button)
        return card
    }

    private func makeButton(title: String, action: Selector) -> ThemeButton {
        let button = ThemeButton()
        button.setTitle(title, for: .normal)
        button.heightAnchor.constraint(equalToConstant: 50).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    // MARK: - Toggle actions

    @objc private func toggleLiveScore() {
        if let activity = liveScoreActivity {
            Task { @MainActor in
                await activity.end(using: nil, dismissalPolicy: .default)
                self.liveScoreActivity = nil
                self.liveScoreButton?.setTitle("Start Live Score", for: .normal)
            }
        } else {
            do {
                liveScoreActivity = try Activity.request(
                    attributes: CIOLiveScoreAttributes(
                        activityInstanceId: UUID().uuidString,
                        homeTeam: .init(name: "HME"),
                        awayTeam: .init(name: "AWY"),
                        sport: "Demo"
                    ),
                    contentState: .init(homeScore: 0, awayScore: 0, period: "1st"),
                    pushType: .token
                )
                liveScoreButton?.setTitle("End Live Score", for: .normal)
            } catch {
                showToast(withMessage: "Failed to start Live Score: \(error.localizedDescription)")
            }
        }
    }

    @objc private func toggleDelivery() {
        if let activity = deliveryActivity {
            Task { @MainActor in
                await activity.end(using: nil, dismissalPolicy: .default)
                self.deliveryActivity = nil
                self.deliveryButton?.setTitle("Start Delivery Tracking", for: .normal)
            }
        } else {
            do {
                deliveryActivity = try Activity.request(
                    attributes: CIODeliveryTrackingAttributes(
                        activityInstanceId: UUID().uuidString,
                        branding: demoBranding,
                        orderId: "ORD-001"
                    ),
                    contentState: .init(
                        statusMessage: "Out for delivery",
                        stepCurrent: 2,
                        stepTotal: 4,
                        estimatedArrival: Date().addingTimeInterval(3600)
                    ),
                    pushType: .token
                )
                deliveryButton?.setTitle("End Delivery Tracking", for: .normal)
            } catch {
                showToast(withMessage: "Failed to start Delivery Tracking: \(error.localizedDescription)")
            }
        }
    }

    @objc private func toggleCountdown() {
        if let activity = countdownActivity {
            Task { @MainActor in
                await activity.end(using: nil, dismissalPolicy: .default)
                self.countdownActivity = nil
                self.countdownButton?.setTitle("Start Countdown Timer", for: .normal)
            }
        } else {
            do {
                countdownActivity = try Activity.request(
                    attributes: CIOCountdownTimerAttributes(
                        activityInstanceId: UUID().uuidString,
                        branding: demoBranding,
                        title: "Flash Sale"
                    ),
                    contentState: .init(
                        targetDate: Date().addingTimeInterval(3600),
                        statusMessage: "Sale ends in",
                        expiredMessage: "Sale is live!"
                    ),
                    pushType: .token
                )
                countdownButton?.setTitle("End Countdown Timer", for: .normal)
            } catch {
                showToast(withMessage: "Failed to start Countdown Timer: \(error.localizedDescription)")
            }
        }
    }

    @objc private func toggleFlight() {
        if let activity = flightActivity {
            Task { @MainActor in
                await activity.end(using: nil, dismissalPolicy: .default)
                self.flightActivity = nil
                self.flightButton?.setTitle("Start Flight Status", for: .normal)
            }
        } else {
            do {
                let now = Date()
                flightActivity = try Activity.request(
                    attributes: CIOFlightStatusAttributes(
                        activityInstanceId: UUID().uuidString,
                        branding: demoBranding,
                        flightNumber: "CIO101",
                        origin: .init(code: "SFO", city: "San Francisco"),
                        destination: .init(code: "JFK", city: "New York")
                    ),
                    contentState: .init(
                        statusMessage: "On Time",
                        gate: "B12",
                        terminal: "2",
                        scheduledDeparture: now.addingTimeInterval(1800),
                        estimatedArrival: now.addingTimeInterval(21600)
                    ),
                    pushType: .token
                )
                flightButton?.setTitle("End Flight Status", for: .normal)
            } catch {
                showToast(withMessage: "Failed to start Flight Status: \(error.localizedDescription)")
            }
        }
    }

    @objc private func toggleAuction() {
        if let activity = auctionActivity {
            Task { @MainActor in
                await activity.end(using: nil, dismissalPolicy: .default)
                self.auctionActivity = nil
                self.auctionButton?.setTitle("Start Auction Bid", for: .normal)
            }
        } else {
            do {
                auctionActivity = try Activity.request(
                    attributes: CIOAuctionBidAttributes(
                        activityInstanceId: UUID().uuidString,
                        branding: demoBranding,
                        itemTitle: "Vintage Watch"
                    ),
                    contentState: .init(
                        currentBid: "100.00",
                        bidCount: 5,
                        endTime: Date().addingTimeInterval(3600),
                        statusMessage: "You've been outbid"
                    ),
                    pushType: .token
                )
                auctionButton?.setTitle("End Auction Bid", for: .normal)
            } catch {
                showToast(withMessage: "Failed to start Auction Bid: \(error.localizedDescription)")
            }
        }
    }
}
