import UIKit

final class ChatMessageCell: UICollectionViewCell {
    static let reuseIdentifier = "ChatMessageCell"

    private let rowView = UIView()
    private let bubbleView = UIView()
    private let stackView = UIStackView()
    private let speakerLabel = UILabel()
    private let reasoningLabel = PaddingLabel()
    private let messageLabel = UILabel()
    private let footerLabel = UILabel()
    private let statsLabel = UILabel()

    private var row: ChatTimelineMessageRow?
    private var editAction: ((MessageDisplayItem) -> Void)?
    private var deleteAction: ((String) -> Void)?
    private var regenerateAction: (() -> Void)?
    private var bubbleLeadingConstraint: NSLayoutConstraint?
    private var bubbleTrailingConstraint: NSLayoutConstraint?
    private var bubbleCenterXConstraint: NSLayoutConstraint?
    private var bubbleWidthConstraint: NSLayoutConstraint?
    private var activeAlignmentConstraints: [NSLayoutConstraint] = []
    private var topConstraint: NSLayoutConstraint?
    private var bottomConstraint: NSLayoutConstraint?

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
        row = nil
        editAction = nil
        deleteAction = nil
        regenerateAction = nil
        messageLabel.attributedText = nil
        reasoningLabel.text = nil
        speakerLabel.text = nil
        footerLabel.text = nil
        statsLabel.text = nil
    }

    func apply(
        row: ChatTimelineMessageRow,
        onEdit: @escaping (MessageDisplayItem) -> Void,
        onDelete: @escaping (String) -> Void,
        onRegenerate: @escaping () -> Void
    ) {
        self.row = row
        editAction = onEdit
        deleteAction = onDelete
        regenerateAction = onRegenerate

        let item = row.item
        let isUser = item.role == "user"
        let isSystem = item.role == "system"

        contentView.accessibilityIdentifier = "chat.message.\(item.role).\(item.id)"
        messageLabel.accessibilityIdentifier = "chat.message.\(item.role).\(item.id)"
        messageLabel.accessibilityLabel = item.content

        activateAlignmentConstraints(isUser: isUser, isSystem: isSystem)
        rowView.isHidden = false
        speakerLabel.isHidden = isUser || isSystem || row.isGroupedWithPrevious || item.speakerName == nil
        speakerLabel.text = speakerName(for: item)
        reasoningLabel.isHidden = reasoningText(for: row).isEmpty
        reasoningLabel.text = reasoningText(for: row)
        footerLabel.isHidden = row.isGroupedWithNext
        footerLabel.text = item.createdAt.openChatRelativeTimestamp() + (row.isStreaming ? "  ..." : "")
        statsLabel.isHidden = !row.showDetailedStats || row.isStreaming || row.isGroupedWithNext || item.streamingStats == nil
        statsLabel.text = statsText(for: item.streamingStats)

        let textColor: UIColor = isUser ? .white : .label
        let font = UIFont.preferredFont(forTextStyle: .body)
        messageLabel.attributedText = ChatTimelineTextCache.shared.attributedText(
            messageID: item.id,
            for: item.content,
            revision: item.contentRenderRevision,
            role: item.role,
            color: textColor,
            font: font,
            renderedMarkdown: item.renderedMarkdown
        )
        messageLabel.textColor = textColor
        messageLabel.font = font
        messageLabel.tintColor = isUser ? .white : tintColor

        bubbleView.backgroundColor = bubbleColor(isUser: isUser, isSystem: isSystem)
        bubbleView.layer.borderWidth = isUser || isSystem ? 0 : 0.5
        bubbleView.layer.borderColor = UIColor.separator.withAlphaComponent(0.12).cgColor
        bubbleView.layer.cornerRadius = 18
        bubbleView.layer.cornerCurve = .continuous
        bubbleView.layer.shadowOpacity = isSystem ? 0 : 0.05
        bubbleView.layer.shadowRadius = row.isGroupedWithPrevious || row.isGroupedWithNext ? 1 : 3
        bubbleView.layer.shadowOffset = CGSize(width: 0, height: 1)
        bubbleView.layer.shadowColor = UIColor.black.cgColor

        if isSystem {
            messageLabel.textAlignment = .center
            footerLabel.isHidden = true
            speakerLabel.isHidden = true
            statsLabel.isHidden = true
            reasoningLabel.isHidden = true
        } else if isUser {
            messageLabel.textAlignment = .natural
        } else {
            messageLabel.textAlignment = .natural
        }

        topConstraint?.constant = CGFloat(row.topPadding)
        bottomConstraint?.constant = row.isGroupedWithNext ? -1 : -3
        setNeedsLayout()
    }

    override func layoutSubviews() {
        if let row {
            let width = max(contentView.bounds.width, bounds.width, 1)
            applyLayoutMetrics(ChatTimelineLayout.bubbleMetrics(for: row, containerWidth: width))
        }
        super.layoutSubviews()
        updateBubbleShadowPath()
    }

    private func configure() {
        contentView.addSubview(rowView)
        rowView.addSubview(bubbleView)
        bubbleView.addSubview(stackView)

        rowView.translatesAutoresizingMaskIntoConstraints = false
        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 5
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12)

        speakerLabel.font = .preferredFont(forTextStyle: .caption1)
        speakerLabel.textColor = tintColor
        speakerLabel.numberOfLines = 1

        reasoningLabel.font = .preferredFont(forTextStyle: .caption2)
        reasoningLabel.textColor = .systemPurple
        reasoningLabel.numberOfLines = 4
        reasoningLabel.backgroundColor = UIColor.systemPurple.withAlphaComponent(0.06)
        reasoningLabel.layer.cornerRadius = 8
        reasoningLabel.layer.masksToBounds = true
        reasoningLabel.contentInsets = UIEdgeInsets(top: 6, left: 8, bottom: 6, right: 8)

        messageLabel.numberOfLines = 0
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        footerLabel.font = .preferredFont(forTextStyle: .caption2)
        footerLabel.textColor = .tertiaryLabel
        footerLabel.numberOfLines = 1

        statsLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        statsLabel.textColor = .secondaryLabel
        statsLabel.numberOfLines = 1

        stackView.addArrangedSubview(speakerLabel)
        stackView.addArrangedSubview(reasoningLabel)
        stackView.addArrangedSubview(messageLabel)
        stackView.addArrangedSubview(footerLabel)
        stackView.addArrangedSubview(statsLabel)

        let interaction = UIContextMenuInteraction(delegate: self)
        bubbleView.addInteraction(interaction)
        bubbleView.isUserInteractionEnabled = true

        bubbleLeadingConstraint = bubbleView.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: 12)
        bubbleTrailingConstraint = bubbleView.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -12)
        bubbleCenterXConstraint = bubbleView.centerXAnchor.constraint(equalTo: rowView.centerXAnchor)
        bubbleWidthConstraint = bubbleView.widthAnchor.constraint(equalToConstant: 280)
        topConstraint = rowView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 7)
        bottomConstraint = rowView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3)

        NSLayoutConstraint.activate([
            rowView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rowView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            topConstraint!,
            bottomConstraint!,
            bubbleWidthConstraint!,
            bubbleView.topAnchor.constraint(equalTo: rowView.topAnchor),
            bubbleView.bottomAnchor.constraint(equalTo: rowView.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: bubbleView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bubbleView.bottomAnchor),
        ])
    }

    private func activateAlignmentConstraints(isUser: Bool, isSystem: Bool) {
        NSLayoutConstraint.deactivate(activeAlignmentConstraints)
        if isSystem {
            activeAlignmentConstraints = [bubbleCenterXConstraint].compactMap { $0 }
        } else if isUser {
            activeAlignmentConstraints = [bubbleTrailingConstraint].compactMap { $0 }
        } else {
            activeAlignmentConstraints = [bubbleLeadingConstraint].compactMap { $0 }
        }
        NSLayoutConstraint.activate(activeAlignmentConstraints)
    }

    private func applyLayoutMetrics(_ metrics: ChatTimelineBubbleMetrics) {
        bubbleWidthConstraint?.constant = metrics.bubbleWidth
        bubbleLeadingConstraint?.constant = metrics.leadingInset
        bubbleTrailingConstraint?.constant = -metrics.trailingInset
        messageLabel.preferredMaxLayoutWidth = metrics.bubbleWidth - 24
        reasoningLabel.preferredMaxLayoutWidth = metrics.bubbleWidth - 24
    }

    private func updateBubbleShadowPath() {
        guard !bubbleView.bounds.isEmpty, bubbleView.layer.shadowOpacity > 0 else {
            bubbleView.layer.shadowPath = nil
            return
        }
        bubbleView.layer.shadowPath = UIBezierPath(
            roundedRect: bubbleView.bounds,
            cornerRadius: bubbleView.layer.cornerRadius
        ).cgPath
    }

    private func bubbleColor(isUser: Bool, isSystem: Bool) -> UIColor {
        if isSystem {
            return UIColor.tertiarySystemFill
        }
        return isUser ? tintColor : .secondarySystemGroupedBackground
    }

    private func reasoningText(for row: ChatTimelineMessageRow) -> String {
        if let reasoning = row.item.reasoningContent?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reasoning.isEmpty {
            let suffix = reasoning.count > 1_400 ? reasoning.suffix(1_400) : Substring(reasoning)
            return "\(String(localized: "Character Thinking"))\n\(suffix)"
        }
        if row.isStreaming && row.item.content.isEmpty {
            return String(localized: "Character thinking…")
        }
        return ""
    }

    private func statsText(for stats: StreamingStats?) -> String? {
        guard let stats else { return nil }
        return String(
            format: "in %d  out %d  %.1f t/s  %@ left",
            stats.inputTokens,
            stats.outputTokens,
            stats.tokensPerSecond,
            stats.contextRemainingFormatted
        )
    }

    private func speakerName(for item: MessageDisplayItem) -> String {
        if let speakerName = item.speakerName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !speakerName.isEmpty {
            return speakerName
        }
        switch item.role {
        case "user":
            return String(localized: "You")
        case "assistant":
            return String(localized: "Assistant")
        default:
            return String(localized: "System")
        }
    }
}

extension ChatMessageCell: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let row else { return nil }
        let item = row.item
        return UIContextMenuConfiguration(identifier: item.id as NSString, previewProvider: nil) { [weak self] _ in
            guard let self else { return UIMenu(children: []) }
            if item.role == "user" {
                let edit = UIAction(title: String(localized: "Edit"), image: UIImage(systemName: "pencil")) { _ in
                    self.editAction?(item)
                }
                edit.attributes = row.canEdit ? [] : [.disabled]
                let copy = UIAction(title: String(localized: "Copy"), image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = item.content
                }
                return UIMenu(children: [edit, copy])
            }

            let copy = UIAction(title: String(localized: "Copy"), image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.string = item.content
            }
            let regenerate = UIAction(title: String(localized: "Regenerate"), image: UIImage(systemName: "arrow.clockwise")) { _ in
                self.regenerateAction?()
            }
            regenerate.attributes = row.isStreaming ? [.disabled] : []
            let delete = UIAction(title: String(localized: "Delete"), image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                self.deleteAction?(item.id)
            }
            delete.attributes = row.isStreaming ? [.disabled, .destructive] : [.destructive]
            return UIMenu(children: [copy, regenerate, delete])
        }
    }
}
