import UIKit

final class ChatTimelineLoadEarlierCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatTimelineLoadEarlierCell"

    private let button = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .medium)
    private var minimumHeightConstraint: NSLayoutConstraint?
    private var action: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(hasMore: Bool, isLoading: Bool, action: @escaping () -> Void) {
        self.action = action
        button.isHidden = isLoading || !hasMore
        activityIndicator.isHidden = !isLoading
        minimumHeightConstraint?.constant = hasMore || isLoading ? 36 : 0
        if isLoading {
            activityIndicator.startAnimating()
        } else {
            activityIndicator.stopAnimating()
        }
    }

    private func configure() {
        contentView.addSubview(button)
        contentView.addSubview(activityIndicator)
        button.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false

        button.setTitle(String(localized: "Load earlier messages"), for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        button.addTarget(self, action: #selector(loadEarlier), for: .touchUpInside)
        button.accessibilityIdentifier = "chat.timeline.loadEarlier"
        minimumHeightConstraint = contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 0)

        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            button.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            button.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            activityIndicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            minimumHeightConstraint!,
        ])
    }

    @objc private func loadEarlier() {
        action?()
    }
}

final class ChatTimelineDateSeparatorCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatTimelineDateSeparatorCell"

    private let label = PaddingLabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(date: Date) {
        label.text = date.formatted(date: .abbreviated, time: .omitted)
    }

    private func configure() {
        contentView.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .caption2)
        label.textColor = .secondaryLabel
        label.backgroundColor = UIColor.secondarySystemGroupedBackground.withAlphaComponent(0.78)
        label.layer.cornerRadius = 10
        label.layer.masksToBounds = true
        label.textAlignment = .center
        label.contentInsets = UIEdgeInsets(top: 4, left: 10, bottom: 4, right: 10)
        label.accessibilityIdentifier = "chat.timeline.dateSeparator"

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
        ])
    }
}

final class ChatTimelineEmptyCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatTimelineEmptyCell"

    private let stackView = UIStackView()
    private let icon = UIImageView(image: UIImage(systemName: "bubble.left.and.text.bubble.right"))
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configure() {
        contentView.accessibilityIdentifier = "chat.emptyState"
        contentView.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 12

        icon.tintColor = .secondaryLabel
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 42, weight: .light)
        label.text = String(localized: "Send a message to start the conversation.")
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0

        stackView.addArrangedSubview(icon)
        stackView.addArrangedSubview(label)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -48),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 32),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -32),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 420),
        ])
    }
}

final class ChatTimelineExtractionCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatTimelineExtractionCell"

    private let label = UILabel()
    private var dismissAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        dismissAction = nil
    }

    func apply(item: ChatTimelineExtractionItem, onDismiss: @escaping () -> Void) {
        dismissAction = onDismiss
        switch item.state {
        case .idle:
            label.text = nil
        case .extracting:
            label.text = String(localized: "Extracting memories…")
        case .completed:
            label.text = String(localized: "Memorized \(item.count ?? 0) entries")
            perform(#selector(dismissIfNeeded), with: nil, afterDelay: 3)
        case .failed:
            let description = item.description ?? ""
            label.text = description.isEmpty
                ? String(localized: "Memory extraction failed")
                : "\(String(localized: "Memory extraction failed"))\n\(description)"
            perform(#selector(dismissIfNeeded), with: nil, afterDelay: 5)
        }
    }

    private func configure() {
        contentView.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.numberOfLines = 3
        label.textAlignment = .center
        label.accessibilityIdentifier = "chat.memoryExtractionIndicator"

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
    }

    @objc private func dismissIfNeeded() {
        dismissAction?()
    }
}

final class ChatTimelineDiagnosticsCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatTimelineDiagnosticsCell"

    private let label = PaddingLabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(summary: String) {
        label.text = "\(String(localized: "Retrieval Trace"))  \(summary)"
    }

    private func configure() {
        contentView.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .caption1)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        label.backgroundColor = .secondarySystemGroupedBackground
        label.layer.cornerRadius = 8
        label.layer.masksToBounds = true
        label.contentInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        label.accessibilityIdentifier = "chat.retrievalTrace"

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12),
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.widthAnchor.constraint(lessThanOrEqualToConstant: 720),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
    }
}

final class ChatTimelinePerformanceMarkerCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatTimelinePerformanceMarkerCell"

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityLabel = "Performance generation complete"
        accessibilityIdentifier = "chat.performanceGenerationComplete"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class PaddingLabel: UILabel {
    var contentInsets = UIEdgeInsets.zero {
        didSet { invalidateIntrinsicContentSize() }
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInsets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(
            width: size.width + contentInsets.left + contentInsets.right,
            height: size.height + contentInsets.top + contentInsets.bottom
        )
    }
}
