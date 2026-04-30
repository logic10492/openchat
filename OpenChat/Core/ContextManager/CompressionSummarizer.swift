import Foundation

struct CompressionSummarizer: Sendable {
    let apiClient: APIClient
    let endpoint: APIEndpointConfig

    func summarize(
        previousSummary: String?,
        messages: [MessageRecord],
        maxTokens: Int
    ) async throws -> String {
        let prompt = """
        You are performing a CONTEXT CHECKPOINT COMPACTION for an ongoing roleplay conversation.

        Produce a durable handoff summary that will replace older transcript items.
        Preserve:
        - key facts, character decisions, relationship state, emotional state, and plot state
        - unresolved promises, constraints, and user preferences
        - details needed to continue without rereading the compressed source messages

        Do not invent new facts. Do not add commentary about the compression task.
        Keep the summary under \(maxTokens) tokens.
        """

        var sourceParts: [String] = []
        if let previousSummary, !previousSummary.isEmpty {
            sourceParts.append("[Existing compressed context]\n\(previousSummary)")
        }
        sourceParts.append(messages.map { "\($0.role): \($0.content)" }.joined(separator: "\n"))

        let response = try await apiClient.sendMessage(
            messages: [
                ChatMessage(role: "system", content: prompt),
                ChatMessage(role: "user", content: sourceParts.joined(separator: "\n\n"))
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
