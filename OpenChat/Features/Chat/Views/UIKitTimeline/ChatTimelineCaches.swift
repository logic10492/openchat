import Foundation
import UIKit

@MainActor
final class ChatTimelineTextCache {
    static let shared = ChatTimelineTextCache()

    private let cache = NSCache<NSString, NSAttributedString>()

    private init() {
        cache.countLimit = 900
    }

    func attributedText(
        messageID: String,
        for text: String,
        revision: Int,
        role: String,
        color: UIColor,
        font: UIFont,
        renderedMarkdown: AttributedString? = nil
    ) -> NSAttributedString {
        let key = [
            messageID,
            role,
            "\(revision)",
            "\(font.pointSize)",
            "\(UITraitCollection.current.userInterfaceStyle.rawValue)",
        ].joined(separator: "|") as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let attributed: NSAttributedString
        if let renderedMarkdown {
            attributed = normalize(NSAttributedString(renderedMarkdown), color: color, font: font)
        } else {
            attributed = makeAttributedText(text: text, color: color, font: font)
        }
        cache.setObject(attributed, forKey: key)
        return attributed
    }

    private func makeAttributedText(text: String, color: UIColor, font: UIFont) -> NSAttributedString {
        guard let parsed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return NSAttributedString(string: text, attributes: [.foregroundColor: color, .font: font])
        }

        return normalize(NSAttributedString(parsed), color: color, font: font)
    }

    private func normalize(_ text: NSAttributedString, color: UIColor, font: UIFont) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: text)
        let range = NSRange(location: 0, length: mutable.length)
        mutable.addAttributes(
            [
                NSAttributedString.Key.foregroundColor: color,
                NSAttributedString.Key.font: font,
            ],
            range: range
        )
        return mutable
    }
}

@MainActor
final class ChatTimelineHeightCache {
    static let shared = ChatTimelineHeightCache()

    private let cache = NSCache<NSString, NSNumber>()

    private init() {
        cache.countLimit = 1_600
    }

    func height(for key: String) -> CGFloat? {
        cache.object(forKey: key as NSString).map { CGFloat(truncating: $0) }
    }

    func setHeight(_ height: CGFloat, for key: String) {
        cache.setObject(NSNumber(value: Double(height)), forKey: key as NSString)
    }

    static func key(for row: ChatTimelineMessageRow, width: CGFloat) -> String {
        let bucketedWidth = Int(width.rounded(.down))
        return [
            row.item.id,
            row.item.role,
            "\(row.item.contentRenderRevision)",
            "\(row.item.reasoningRenderRevision)",
            "\(row.item.streamingStats != nil)",
            "\(row.showDetailedStats)",
            "\(row.isStreaming)",
            "\(row.isGroupedWithPrevious)",
            "\(row.isGroupedWithNext)",
            "\(bucketedWidth)",
        ].joined(separator: "|")
    }
}
