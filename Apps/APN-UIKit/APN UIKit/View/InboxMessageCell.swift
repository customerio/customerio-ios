import CioMessagingInApp
import UIKit

final class InboxMessageCell: UITableViewCell {
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
        containerView.backgroundColor = message.opened ? .systemBackground : .secondarySystemBackground

        queueIdLabel.text = message.queueId
        dateLabel.text = dateFormatter.string(from: message.sentAt)
        propertiesLabel.text = message.properties.isEmpty ? "No properties" : "\(message.properties)"

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
