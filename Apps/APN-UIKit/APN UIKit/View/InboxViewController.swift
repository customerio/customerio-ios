import CioMessagingInApp
import UIKit

class InboxViewController: BaseViewController, UITableViewDelegate, UITableViewDataSource, InboxMessageChangeListener {
    static func newInstance() -> InboxViewController {
        UIStoryboard.getViewController(identifier: "InboxViewController")
    }

    @IBOutlet var tableView: UITableView!
    @IBOutlet var emptyStateView: UIView!
    @IBOutlet var emptyStateLabel: UILabel!
    @IBOutlet var statusLabel: UILabel!

    private var messages: [InboxMessage] = []
    private let inbox = MessagingInApp.shared.inbox
    private let refreshControl = UIRefreshControl()

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

    deinit {
        inbox.removeChangeListener(self)
    }

    private func setupUI() {
        title = "Inbox Messages"
        tableView.delegate = self
        tableView.dataSource = self
        tableView.estimatedRowHeight = 120
        tableView.rowHeight = UITableView.automaticDimension
        tableView.separatorStyle = .none
        tableView.backgroundColor = .systemBackground

        // Hide status label and remove its space
        statusLabel.isHidden = true
        // Adjust additional safe area to compensate for hidden status label
        // Status label: 8pt top + 20pt height + 16pt bottom = 44pt total
        additionalSafeAreaInsets = UIEdgeInsets(top: -44, left: 0, bottom: 0, right: 0)

        // Add pull-to-refresh
        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        tableView.refreshControl = refreshControl

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

        if isEmpty {
            emptyStateLabel.text = "No messages\n\nYour inbox is empty"
            emptyStateLabel.textAlignment = .center
            emptyStateLabel.textColor = .gray
            emptyStateLabel.numberOfLines = 0
            // Show empty state as background view to keep pull-to-refresh functional
            tableView.backgroundView = emptyStateView
            emptyStateView.isHidden = false
        } else {
            tableView.backgroundView = nil
            emptyStateView.isHidden = true
        }
    }

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
        let cell = tableView.dequeueReusableCell(withIdentifier: "InboxMessageCell") ?? {
            let newCell = UITableViewCell(style: .default, reuseIdentifier: "InboxMessageCell")
            newCell.selectionStyle = .none
            return newCell
        }()

        let message = messages[indexPath.row]
        configureCell(cell, with: message, at: indexPath)
        return cell
    }

    private func configureCell(_ cell: UITableViewCell, with message: InboxMessage, at indexPath: IndexPath) {
        // Clear previous subviews
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }

        // Create custom layout similar to Android with elevation
        let containerView = createContainerView(for: message)
        cell.contentView.addSubview(containerView)
        cell.backgroundColor = .clear

        // Create labels
        let queueIdLabel = createQueueIdLabel(for: message)
        let dateLabel = createDateLabel(for: message)
        let propertiesLabel = createPropertiesLabel(for: message)
        let buttonsStack = createActionButtonsStack(for: message, at: indexPath)

        containerView.addSubview(queueIdLabel)
        containerView.addSubview(dateLabel)
        containerView.addSubview(propertiesLabel)
        containerView.addSubview(buttonsStack)

        // Layout constraints
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
            containerView.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 12),
            containerView.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -12),
            containerView.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8),

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

    private func createContainerView(for message: InboxMessage) -> UIView {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        // Unread messages have gray background, read messages have white background
        containerView.backgroundColor = message.opened ? .systemBackground : .secondarySystemBackground
        containerView.layer.cornerRadius = 8

        // Add elevation (shadow) like Android Material cards
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOffset = CGSize(width: 0, height: 2)
        containerView.layer.shadowOpacity = 0.1
        containerView.layer.shadowRadius = 4
        containerView.layer.masksToBounds = false

        return containerView
    }

    private func createQueueIdLabel(for message: InboxMessage) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = message.queueId
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.numberOfLines = 1
        return label
    }

    private func createDateLabel(for message: InboxMessage) -> UILabel {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM dd, yyyy h:mm a"
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = dateFormatter.string(from: message.sentAt)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        return label
    }

    private func createPropertiesLabel(for message: InboxMessage) -> UILabel {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = message.properties.isEmpty ? "No properties" : "\(message.properties)"
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        return label
    }

    private func createActionButtonsStack(for message: InboxMessage, at indexPath: IndexPath) -> UIStackView {
        let buttonsStack = UIStackView()
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false
        buttonsStack.axis = .horizontal
        buttonsStack.spacing = 8
        buttonsStack.distribution = .fillEqually

        // Mark Read/Unread button
        let readButton = createActionButton(
            imageName: message.opened ? "inbox-unread" : "inbox-read",
            tintColor: .darkGray,
            tag: indexPath.row * 3 + 0
        )
        readButton.addTarget(self, action: #selector(toggleReadTapped(_:)), for: .touchUpInside)
        buttonsStack.addArrangedSubview(readButton)

        // Track Click button
        let trackButton = createActionButton(
            imageName: "inbox-track",
            tintColor: .darkGray,
            tag: indexPath.row * 3 + 1
        )
        trackButton.addTarget(self, action: #selector(trackClickTapped(_:)), for: .touchUpInside)
        buttonsStack.addArrangedSubview(trackButton)

        // Delete button
        let deleteButton = createActionButton(
            imageName: "inbox-delete",
            tintColor: .systemRed,
            tag: indexPath.row * 3 + 2
        )
        deleteButton.addTarget(self, action: #selector(deleteTapped(_:)), for: .touchUpInside)
        buttonsStack.addArrangedSubview(deleteButton)

        return buttonsStack
    }

    private func createActionButton(imageName: String, tintColor: UIColor, tag: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(named: imageName)?.withRenderingMode(.alwaysTemplate), for: .normal)
        button.tintColor = tintColor
        button.tag = tag
        return button
    }

    // MARK: - UITableViewDelegate

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        120
    }

    // MARK: - InboxMessageChangeListener

    func onMessagesChanged(messages: [InboxMessage]) {
        Task { @MainActor in
            self.messages = messages
            tableView.reloadData()
            updateEmptyState()
        }
    }
}

// MARK: - Action Handlers

private extension InboxViewController {
    @objc func trackClickTapped(_ sender: UIButton) {
        let index = sender.tag / 3
        guard index < messages.count else { return }
        let message = messages[index]
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

    @objc func toggleReadTapped(_ sender: UIButton) {
        let index = sender.tag / 3
        guard index < messages.count else { return }
        let message = messages[index]

        if message.opened {
            inbox.markMessageUnopened(message: message)
            showToast(withMessage: "Marked as unread")
        } else {
            inbox.markMessageOpened(message: message)
            showToast(withMessage: "Marked as read")
        }

        // Reload the specific row to update button appearance
        tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
    }

    @objc func deleteTapped(_ sender: UIButton) {
        let index = sender.tag / 3
        guard index < messages.count else { return }
        let message = messages[index]
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
