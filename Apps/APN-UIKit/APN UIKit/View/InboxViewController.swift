import CioMessagingInApp
import CioMessagingInbox
import SwiftUI
import UIKit

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
