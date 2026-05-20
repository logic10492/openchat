import SwiftUI

struct TextContentBlock: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case text
    }

    let id: Int
    var text: String
    var kind: Kind

    init(id: Int, text: String, kind: Kind = .text) {
        self.id = id
        self.text = text
        self.kind = kind
    }

    static func makeBlocks(from text: String) -> [TextContentBlock] {
        split(text).enumerated().map { offset, piece in
            TextContentBlock(id: offset, text: piece)
        }
    }

    static func makeDisplayBlocks(from text: String) -> [TextContentBlock] {
        makeBlocks(from: compactExcessBlankLines(in: text))
    }

    static func appending(_ delta: String, to blocks: [TextContentBlock]) -> [TextContentBlock] {
        guard !delta.isEmpty else { return blocks }

        var result = blocks
        let existingTail = result.popLast()
        let baseID = existingTail?.id ?? 0
        let combinedTail = (existingTail?.text ?? "") + delta
        let tailPieces = split(combinedTail)

        guard !tailPieces.isEmpty else { return result }

        for (offset, piece) in tailPieces.enumerated() {
            result.append(
                TextContentBlock(
                    id: baseID + offset,
                    text: piece,
                    kind: existingTail?.kind ?? .text
                )
            )
        }

        return result
    }

    static func appendingDisplay(_ delta: String, to blocks: [TextContentBlock]) -> [TextContentBlock] {
        guard !delta.isEmpty else { return blocks }

        var result = blocks
        var tail = ""
        while let last = result.last, last.text.allSatisfy({ $0 == "\n" }) {
            tail = result.removeLast().text + tail
        }
        if let existingTail = result.popLast() {
            tail = existingTail.text + tail
        }

        let baseID = result.last.map { $0.id + 1 } ?? 0
        let tailPieces = split(compactExcessBlankLines(in: tail + delta))

        for (offset, piece) in tailPieces.enumerated() {
            result.append(TextContentBlock(id: baseID + offset, text: piece))
        }

        return result
    }

    private static func compactExcessBlankLines(in text: String) -> String {
        text.replacingOccurrences(
            of: #"(?:\r?\n[ \t]*){3,}"#,
            with: "\n\n",
            options: .regularExpression
        )
    }

    private static func split(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        let maximumBlockLength = 1_200
        var pieces: [String] = []
        var buffer = ""
        buffer.reserveCapacity(min(text.count, maximumBlockLength))

        for character in text {
            buffer.append(character)
            if character == "\n" || buffer.count >= maximumBlockLength {
                pieces.append(buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }

        if !buffer.isEmpty {
            pieces.append(buffer)
        }

        return pieces
    }
}

enum MarkdownRenderPolicy {
    static func refreshDelay(forCharacterCount count: Int) -> Duration {
        switch count {
        case 0..<500:
            .milliseconds(30)
        case 500..<1_500:
            .milliseconds(50)
        case 1_500..<3_000:
            .milliseconds(75)
        default:
            .milliseconds(100)
        }
    }
}

private struct RenderedMarkdownBlock {
    let text: String
    let attributed: AttributedString
}

private actor MarkdownRenderCache {
    static let shared = MarkdownRenderCache()

    private let maximumEntries = 256
    private var rendered: [String: AttributedString] = [:]
    private var failed: Set<String> = []
    private var order: [String] = []

    func attributedString(for text: String) -> AttributedString? {
        if let cached = rendered[text] {
            return cached
        }
        if failed.contains(text) {
            return nil
        }

        guard let attributed = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            rememberFailure(for: text)
            return nil
        }

        rendered[text] = attributed
        rememberKey(text)
        return attributed
    }

    private func rememberFailure(for text: String) {
        failed.insert(text)
        rememberKey(text)
    }

    private func rememberKey(_ key: String) {
        order.append(key)

        while order.count > maximumEntries {
            let expired = order.removeFirst()
            rendered.removeValue(forKey: expired)
            failed.remove(expired)
        }
    }
}

struct MarkdownTextView: View {
    private let blocks: [TextContentBlock]

    init(text: String) {
        self.blocks = TextContentBlock.makeBlocks(from: text)
    }

    init(blocks: [TextContentBlock]) {
        self.blocks = blocks
    }

    var body: some View {
        SegmentedMarkdownTextView(blocks: blocks)
            .textSelection(.enabled)
    }
}

private struct SegmentedMarkdownTextView: View {
    let blocks: [TextContentBlock]

    private var characterCount: Int {
        blocks.reduce(0) { $0 + $1.text.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(blocks) { block in
                MarkdownTextBlockView(block: block, totalCharacterCount: characterCount)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownTextBlockView: View {
    let block: TextContentBlock
    let totalCharacterCount: Int
    @State private var renderedBlock: RenderedMarkdownBlock?

    var body: some View {
        Group {
            if let renderedBlock, renderedBlock.text == block.text {
                Text(renderedBlock.attributed)
            } else {
                Text(block.text)
            }
        }
        .textSelection(.enabled)
        .task(id: block.text) {
            await refreshMarkdownBlock()
        }
    }

    private func refreshMarkdownBlock() async {
        let snapshot = block
        let delay = MarkdownRenderPolicy.refreshDelay(forCharacterCount: totalCharacterCount)

        do {
            try await Task.sleep(for: delay)
        } catch {
            return
        }

        guard !Task.isCancelled else { return }
        if let attributed = await MarkdownRenderCache.shared.attributedString(for: snapshot.text) {
            renderedBlock = RenderedMarkdownBlock(text: snapshot.text, attributed: attributed)
        } else {
            renderedBlock = nil
        }
    }
}
