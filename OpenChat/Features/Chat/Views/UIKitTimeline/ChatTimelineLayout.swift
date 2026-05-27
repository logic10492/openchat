import UIKit

@MainActor
enum ChatTimelineLayout {
    static func makeCollectionViewLayout() -> UICollectionViewLayout {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.estimatedItemSize = .zero
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = UIEdgeInsets(top: 8, left: 0, bottom: 24, right: 0)
        return layout
    }

    static func bubbleMetrics(
        for row: ChatTimelineMessageRow,
        containerWidth: CGFloat
    ) -> ChatTimelineBubbleMetrics {
        let item = row.item
        if item.role == "system" {
            let horizontalInset: CGFloat = max(44, containerWidth * 0.17)
            return ChatTimelineBubbleMetrics(
                bubbleWidth: max(160, containerWidth - horizontalInset * 2),
                leadingInset: horizontalInset,
                trailingInset: horizontalInset
            )
        }

        if item.role == "user" {
            let leadingInset: CGFloat = max(54, containerWidth * 0.18)
            let trailingInset: CGFloat = 12
            return ChatTimelineBubbleMetrics(
                bubbleWidth: max(120, containerWidth - leadingInset - trailingInset),
                leadingInset: leadingInset,
                trailingInset: trailingInset
            )
        }

        let leadingInset: CGFloat = 12
        let trailingInset: CGFloat = max(54, containerWidth * 0.13)
        return ChatTimelineBubbleMetrics(
            bubbleWidth: max(140, containerWidth - leadingInset - trailingInset),
            leadingInset: leadingInset,
            trailingInset: trailingInset
        )
    }
}

struct ChatTimelineBubbleMetrics {
    let bubbleWidth: CGFloat
    let leadingInset: CGFloat
    let trailingInset: CGFloat
}

@MainActor
enum ChatTimelineHeightMeasurer {
    static func height(
        for item: ChatTimelineItem,
        containerWidth: CGFloat,
        viewportHeight: CGFloat
    ) -> CGFloat {
        switch item {
        case let .loadEarlier(hasMore, isLoading):
            return hasMore || isLoading ? 52 : 1
        case .empty:
            return max(420, viewportHeight - 32)
        case .dateSeparator:
            return ceil(UIFont.preferredFont(forTextStyle: .caption2).lineHeight + 26)
        case let .message(row):
            return messageHeight(for: row, containerWidth: containerWidth)
        case let .extraction(item):
            return extractionHeight(for: item, containerWidth: containerWidth)
        case let .diagnostics(summary):
            return diagnosticsHeight(summary: summary, containerWidth: containerWidth)
        case .performanceCompletion:
            return 1
        }
    }

    static func messageHeight(
        for row: ChatTimelineMessageRow,
        containerWidth: CGFloat
    ) -> CGFloat {
        let key = ChatTimelineHeightCache.key(for: row, width: containerWidth)
        if let cachedHeight = ChatTimelineHeightCache.shared.height(for: key) {
            return cachedHeight
        }

        let item = row.item
        let isUser = item.role == "user"
        let isSystem = item.role == "system"
        let metrics = ChatTimelineLayout.bubbleMetrics(for: row, containerWidth: containerWidth)
        let textWidth = max(24, metrics.bubbleWidth - 24)
        var arrangedHeights: [CGFloat] = []

        if !isUser, !isSystem, !row.isGroupedWithPrevious, speakerName(for: item) != nil {
            arrangedHeights.append(ceil(UIFont.preferredFont(forTextStyle: .caption1).lineHeight))
        }

        let reasoning = reasoningText(for: row)
        if !reasoning.isEmpty {
            arrangedHeights.append(
                measuredPlainTextHeight(
                    reasoning,
                    font: UIFont.preferredFont(forTextStyle: .caption2),
                    width: textWidth - 16,
                    maximumLines: 4
                ) + 12
            )
        }

        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        let bodyColor: UIColor = isUser ? .white : .label
        let attributed = ChatTimelineTextCache.shared.attributedText(
            messageID: item.id,
            for: item.content,
            revision: item.contentRenderRevision,
            role: item.role,
            color: bodyColor,
            font: bodyFont
        )
        arrangedHeights.append(measuredAttributedTextHeight(attributed, width: textWidth))

        if !row.isGroupedWithNext, !isSystem {
            arrangedHeights.append(ceil(UIFont.preferredFont(forTextStyle: .caption2).lineHeight))
        }

        if row.showDetailedStats, !row.isStreaming, !row.isGroupedWithNext, item.streamingStats != nil {
            arrangedHeights.append(ceil(UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular).lineHeight))
        }

        let visibleCount = arrangedHeights.count
        let stackSpacing = CGFloat(max(0, visibleCount - 1)) * 5
        let bubbleHeight = arrangedHeights.reduce(0, +) + stackSpacing + 14
        let bottomPadding: CGFloat = row.isGroupedWithNext ? 1 : 3
        let height = ceil(CGFloat(row.topPadding) + bubbleHeight + bottomPadding)
        ChatTimelineHeightCache.shared.setHeight(height, for: key)
        return height
    }

    private static func extractionHeight(for item: ChatTimelineExtractionItem, containerWidth: CGFloat) -> CGFloat {
        let text: String
        switch item.state {
        case .idle:
            return 1
        case .extracting:
            text = String(localized: "Extracting memories…")
        case .completed:
            text = String(localized: "Memorized \(item.count ?? 0) entries")
        case .failed:
            let description = item.description ?? ""
            text = description.isEmpty
                ? String(localized: "Memory extraction failed")
                : "\(String(localized: "Memory extraction failed"))\n\(description)"
        }

        return measuredPlainTextHeight(
            text,
            font: UIFont.preferredFont(forTextStyle: .caption1),
            width: max(1, containerWidth - 48),
            maximumLines: 3
        ) + 16
    }

    private static func diagnosticsHeight(summary: String, containerWidth: CGFloat) -> CGFloat {
        let text = "\(String(localized: "Retrieval Trace"))  \(summary)"
        let labelWidth = min(720, max(1, containerWidth - 24))
        return measuredPlainTextHeight(
            text,
            font: UIFont.preferredFont(forTextStyle: .caption1),
            width: max(1, labelWidth - 28),
            maximumLines: 0
        ) + 36
    }

    private static func measuredPlainTextHeight(
        _ text: String,
        font: UIFont,
        width: CGFloat,
        maximumLines: Int
    ) -> CGFloat {
        guard !text.isEmpty else { return ceil(font.lineHeight) }
        let boundingHeight = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).height
        if maximumLines > 0 {
            return ceil(min(boundingHeight, font.lineHeight * CGFloat(maximumLines)))
        }
        return ceil(boundingHeight)
    }

    private static func measuredAttributedTextHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        guard text.length > 0 else {
            return ceil(UIFont.preferredFont(forTextStyle: .body).lineHeight)
        }
        let rect = text.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        return ceil(rect.height)
    }

    private static func reasoningText(for row: ChatTimelineMessageRow) -> String {
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

    private static func speakerName(for item: MessageDisplayItem) -> String? {
        guard let speakerName = item.speakerName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !speakerName.isEmpty
        else {
            return nil
        }
        return speakerName
    }
}
