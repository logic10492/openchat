import Foundation

struct CompressionStrategy: ContextStrategyProtocol {
    let apiClient: APIClient
    let endpoint: APIEndpointConfig

    func process(
        allMessages: [MessageRecord],
        tokenBudget: Int
    ) async throws -> [MessageRecord] {
        let totalTokens = allMessages.reduce(into: 0) { $0 += TokenCounter.count(message: $1) }
        guard totalTokens > tokenBudget, allMessages.count > 3 else {
            return allMessages
        }

        let recentBudget = Int(Double(tokenBudget) * 0.7)
        var recentMessages: [MessageRecord] = []
        var recentTokens = 0

        for message in allMessages.reversed() {
            let tokens = TokenCounter.count(message: message)
            if recentTokens + tokens > recentBudget, !recentMessages.isEmpty {
                break
            }
            recentMessages.insert(message, at: 0)
            recentTokens += tokens
        }

        let olderCount = max(allMessages.count - recentMessages.count, 0)
        let olderMessages = Array(allMessages.prefix(olderCount))
        guard !olderMessages.isEmpty else { return recentMessages }

        let summary = try await summarize(messages: olderMessages, maxTokens: max(tokenBudget - recentTokens, 128))
        let summaryMessage = MessageRecord(
            id: UUID().uuidString,
            conversationId: olderMessages.first?.conversationId ?? "",
            role: "system",
            content: "[Previously: \(summary)]",
            tokenCount: TokenCounter.count(summary),
            isCompressed: true,
            originalContent: olderMessages.map(\.content).joined(separator: "\n"),
            sortOrder: olderMessages.last?.sortOrder ?? 0,
            createdAt: olderMessages.last?.createdAt ?? .now,
            reasoningContent: nil
        )
        return [summaryMessage] + recentMessages
    }

    private func summarize(messages: [MessageRecord], maxTokens: Int) async throws -> String {
        let prompt = """
        Summarize the following conversation concisely, preserving key facts, character actions, emotional states, and plot developments.
        Keep the summary under \(maxTokens) tokens.
        Focus on information that matters for continuing the conversation.
        """

        let response = try await apiClient.sendMessage(
            messages: [
                ChatMessage(role: "system", content: prompt),
                ChatMessage(role: "user", content: messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n"))
            ],
            endpoint: endpoint,
            parameters: ModelParameters(maxTokens: maxTokens)
        )
        let summary = response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !summary.isEmpty else {
            throw ContextError.compressionFailed("Compression returned an empty summary")
        }
        return summary
    }
}
