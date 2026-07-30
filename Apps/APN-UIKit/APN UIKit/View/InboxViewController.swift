import CioMessagingInApp
import CioMessagingInbox
import SwiftUI
import UIKit

// MARK: - InboxMessageCell

private class InboxMessageCell: UITableViewCell {
    static let reuseIdentifier = "InboxMessageCell"

    private let containerView = UIView()
    private let queueIdLabel = UILabel()
    private let dateLabel = UILabel()
    private let propertiesLabel = UILabel()
    private let buttonsStack = UIStackView()
    private let readButton = UIButton(type: .system)
    private let trackButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)

    var onReadTapped: (() -> Void)?
    var onTrackTapped: (() -> Void)?
    var onDeleteTapped: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        selectionStyle = .none
        backgroundColor = .clear
        setupContainerView()
        setupLabels()
        setupButtons()
        setupConstraints()
    }

    private func setupContainerView() {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.layer.cornerRadius = 8
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOffset = CGSize(width: 0, height: 2)
        containerView.layer.shadowOpacity = 0.1
        containerView.layer.shadowRadius = 4
        containerView.layer.masksToBounds = false
        contentView.addSubview(containerView)
    }

    private func setupLabels() {
        queueIdLabel.translatesAutoresizingMaskIntoConstraints = false
        queueIdLabel.font = .systemFont(ofSize: 14, weight: .medium)
        queueIdLabel.numberOfLines = 1
        queueIdLabel.accessibilityIdentifier = "inbox_queue_id"
        containerView.addSubview(queueIdLabel)

        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = .systemFont(ofSize: 12)
        dateLabel.textColor = .secondaryLabel
        containerView.addSubview(dateLabel)

        propertiesLabel.translatesAutoresizingMaskIntoConstraints = false
        propertiesLabel.font = .systemFont(ofSize: 12)
        propertiesLabel.textColor = .secondaryLabel
        propertiesLabel.numberOfLines = 2
        propertiesLabel.accessibilityIdentifier = "inbox_properties"
        containerView.addSubview(propertiesLabel)
    }

    private func setupButtons() {
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false
        buttonsStack.axis = .horizontal
        buttonsStack.spacing = 8
        buttonsStack.distribution = .fillEqually

        readButton.addTarget(self, action: #selector(readButtonTapped), for: .touchUpInside)
        trackButton.accessibilityIdentifier = "track_click_button"
        trackButton.accessibilityLabel = "Track Click"
        trackButton.addTarget(self, action: #selector(trackButtonTapped), for: .touchUpInside)
        deleteButton.accessibilityIdentifier = "delete_button"
        deleteButton.accessibilityLabel = "Delete"
        deleteButton.tintColor = .systemRed
        deleteButton.addTarget(self, action: #selector(deleteButtonTapped), for: .touchUpInside)

        buttonsStack.addArrangedSubview(readButton)
        buttonsStack.addArrangedSubview(trackButton)
        buttonsStack.addArrangedSubview(deleteButton)
        containerView.addSubview(buttonsStack)
    }

    private func setupConstraints() {
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),

            queueIdLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            queueIdLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            queueIdLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),

            dateLabel.topAnchor.constraint(equalTo: queueIdLabel.bottomAnchor, constant: 4),
            dateLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            dateLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),

            propertiesLabel.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 4),
            propertiesLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            propertiesLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),

            buttonsStack.topAnchor.constraint(equalTo: propertiesLabel.bottomAnchor, constant: 8),
            buttonsStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            buttonsStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -12),
            buttonsStack.widthAnchor.constraint(equalToConstant: 120)
        ])
    }

    func configure(with message: InboxMessage, dateFormatter: DateFormatter) {
        // Update background based on read/unread state
        containerView.backgroundColor = message.opened ? .systemBackground : .secondarySystemBackground

        // Update labels
        queueIdLabel.text = message.queueId
        dateLabel.text = dateFormatter.string(from: message.sentAt)
        propertiesLabel.text = message.properties.isEmpty ? "No properties" : "\(message.properties)"

        // Update button images
        let readImageName = message.opened ? "inbox-unread" : "inbox-read"
        readButton.accessibilityIdentifier = message.opened ? "mark_unread_button" : "mark_read_button"
        readButton.accessibilityLabel = message.opened ? "Mark as Unread" : "Mark as Read"
        readButton.setImage(UIImage(named: readImageName)?.withRenderingMode(.alwaysTemplate), for: .normal)
        readButton.tintColor = .darkGray

        trackButton.setImage(UIImage(named: "inbox-track")?.withRenderingMode(.alwaysTemplate), for: .normal)
        trackButton.tintColor = .darkGray

        deleteButton.setImage(UIImage(named: "inbox-delete")?.withRenderingMode(.alwaysTemplate), for: .normal)
    }

    @objc private func readButtonTapped() {
        onReadTapped?()
    }

    @objc private func trackButtonTapped() {
        onTrackTapped?()
    }

    @objc private func deleteButtonTapped() {
        onDeleteTapped?()
    }
}

// MARK: - InboxViewController

class InboxViewController: BaseViewController, UITableViewDelegate, UITableViewDataSource, NotificationInboxChangeListener {
    static func newInstance() -> InboxViewController {
        UIStoryboard.getViewController(identifier: "InboxViewController")
    }

    @IBOutlet var tableView: UITableView!
    @IBOutlet var emptyStateView: UIView!
    @IBOutlet var emptyStateLabel: UILabel!

    private var messages: [InboxMessage] = []
    private let inbox = MessagingInApp.shared.inbox
    private let refreshControl = UIRefreshControl()

    // Cached DateFormatter to avoid expensive recreation on every cell
    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM dd, yyyy h:mm a"
        return formatter
    }()

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isNavigationBarHidden = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        // Observer will provide initial messages when registered
        setupObserver()
    }

    /// Pushes a SwiftUI screen that mounts the drop-in `NotificationInboxOverlay` — the bell we expose,
    /// which presents the inbox in its own native sheet. The sample writes no sheet code of its own.
    /// (This headless screen above shows the data API via `addChangeListener`.) iOS 16+ (system detents).
    @objc private func presentOverlayDemo() {
        guard #available(iOS 16.0, *) else { return }
        let host = UIHostingController(rootView: VisualInboxOverlayScreen())
        host.title = "Overlay (SwiftUI)"
        navigationController?.pushViewController(host, animated: true)
    }

    /// Pushes the visual message list as a dedicated screen, without the floating bell or sheet.
    @objc private func presentVisualInboxDemo() {
        guard #available(iOS 13.0, *) else { return }
        let host = UIHostingController(rootView: VisualInboxScreen())
        host.title = "Visual Inbox"
        navigationController?.pushViewController(host, animated: true)
    }

    deinit {
        inbox.removeChangeListener(self)
    }

    private func setupUI() {
        title = "Inbox Messages"
        let visualButton = UIBarButtonItem(
            title: "Visual",
            style: .plain,
            target: self,
            action: #selector(presentVisualInboxDemo)
        )
        navigationItem.rightBarButtonItem = visualButton

        // Keep the drop-in overlay demo alongside the dedicated visual Inbox screen on iOS 16+.
        if #available(iOS 16.0, *) {
            let overlayButton = UIBarButtonItem(
                title: "Overlay",
                style: .plain,
                target: self,
                action: #selector(presentOverlayDemo)
            )
            navigationItem.rightBarButtonItems = [overlayButton, visualButton]
        }
        tableView.delegate = self
        tableView.dataSource = self
        tableView.accessibilityIdentifier = "inbox_messages_list"
        tableView.register(InboxMessageCell.self, forCellReuseIdentifier: InboxMessageCell.reuseIdentifier)
        tableView.estimatedRowHeight = 120
        tableView.rowHeight = UITableView.automaticDimension
        tableView.separatorStyle = .none
        tableView.backgroundColor = .systemBackground

        // Add pull-to-refresh
        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        tableView.refreshControl = refreshControl

        // Allow touches to pass through empty state view to tableView for pull-to-refresh
        emptyStateView.isUserInteractionEnabled = false

        updateEmptyState()
    }

    private func setupObserver() {
        // addChangeListener will immediately call onMessagesChanged with current state
        inbox.addChangeListener(self)
    }

    @objc private func handleRefresh() {
        Task { @MainActor in
            await fetchMessages()
            refreshControl.endRefreshing()
        }
    }

    private func updateEmptyState() {
        let isEmpty = messages.isEmpty
        emptyStateView.isHidden = !isEmpty

        if isEmpty {
            emptyStateLabel.text = "No messages\n\nYour inbox is empty"
            emptyStateLabel.textAlignment = .center
            emptyStateLabel.textColor = .gray
            emptyStateLabel.numberOfLines = 0
        }
    }

    @MainActor
    private func fetchMessages() async {
        let fetchedMessages = await inbox.getMessages()
        messages = fetchedMessages
        tableView.reloadData()
        updateEmptyState()
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        messages.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(
            withIdentifier: InboxMessageCell.reuseIdentifier,
            for: indexPath
        ) as? InboxMessageCell else {
            return UITableViewCell()
        }

        let message = messages[indexPath.row]
        cell.configure(with: message, dateFormatter: dateFormatter)

        // Set up action callbacks
        cell.onReadTapped = { [weak self] in
            self?.toggleReadTapped(for: message, at: indexPath)
        }

        cell.onTrackTapped = { [weak self] in
            self?.trackClickTapped(for: message)
        }

        cell.onDeleteTapped = { [weak self] in
            self?.deleteTapped(for: message)
        }

        return cell
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        120
    }

    // MARK: - NotificationInboxChangeListener

    func onMessagesChanged(messages: [InboxMessage]) {
        self.messages = messages
        tableView.reloadData()
        updateEmptyState()
    }
}

// MARK: - Action Handlers

private extension InboxViewController {
    func trackClickTapped(for message: InboxMessage) {
        showTrackClickDialog(for: message)
    }

    func showTrackClickDialog(for message: InboxMessage) {
        let alert = UIAlertController(
            title: "Track Message Click",
            message: "Enter action name to track (optional)",
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.placeholder = "Action name"
            textField.autocapitalizationType = .none
        }

        let trackAction = UIAlertAction(title: "Track", style: .default) { [weak self, weak alert] _ in
            let actionName = alert?.textFields?.first?.text
            let finalActionName = (actionName?.isEmpty ?? true) ? nil : actionName
            self?.inbox.trackMessageClicked(message: message, actionName: finalActionName)
            self?.showToast(withMessage: "Click tracked")
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)

        alert.addAction(trackAction)
        alert.addAction(cancelAction)

        present(alert, animated: true)
    }

    func toggleReadTapped(for message: InboxMessage, at indexPath: IndexPath) {
        if message.opened {
            inbox.markMessageUnopened(message: message)
            showToast(withMessage: "Marked as unread")
        } else {
            inbox.markMessageOpened(message: message)
            showToast(withMessage: "Marked as read")
        }

        // Reload the specific row to update button appearance
        tableView.reloadRows(at: [indexPath], with: .none)
    }

    func deleteTapped(for message: InboxMessage) {
        showDeleteConfirmationDialog(for: message)
    }

    func showDeleteConfirmationDialog(for message: InboxMessage) {
        let alert = UIAlertController(
            title: "Delete Message",
            message: "Are you sure you want to delete this message?",
            preferredStyle: .alert
        )

        let deleteAction = UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.inbox.markMessageDeleted(message: message)
            self?.showToast(withMessage: "Message deleted")
        }

        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)

        alert.addAction(deleteAction)
        alert.addAction(cancelAction)

        present(alert, animated: true)
    }
}

// MARK: - VisualInboxOverlayScreen

/// Dedicated-screen integration of the visual Inbox message list.
@available(iOS 13.0, *)
private struct VisualInboxScreen: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            NotificationInboxView()
        }
        .accessibilityIdentifier("visual_inbox_screen")
    }
}

/// SwiftUI screen hosting the drop-in `NotificationInboxOverlay` in a `ZStack` — the intended usage.
/// SwiftUI handles bell taps + passthrough; the overlay presents the inbox in its own native sheet.
@available(iOS 16.0, *)
private struct VisualInboxOverlayScreen: View {
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            Text("Your App Content").font(.title2).bold().foregroundColor(.secondary)
            NotificationInboxOverlay()
        }
    }
}
