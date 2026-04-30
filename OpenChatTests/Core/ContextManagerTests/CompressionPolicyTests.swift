import Testing

@testable import OpenChat

@Suite("Compression policy")
struct CompressionPolicyTests {
    @Test func test_standardMode_uses_40_percent_context_window() {
        let endpoint = TestHelpers.makeEndpoint(
            modelName: "deepseek-v4-pro",
            maxContextTokens: 100_000
        )

        let policy = CompressionPolicy(endpoint: endpoint, compressionMode: .standard)

        #expect(policy.effectiveCompactWindowTokens == 100_000)
        #expect(policy.autoCompactTokenLimit == 40_000)
    }

    @Test func test_highIntelligenceMode_uses_25_percent_context_window_times_90_percent() {
        let endpoint = TestHelpers.makeEndpoint(
            modelName: "deepseek-v4-pro",
            maxContextTokens: 100_000
        )

        let policy = CompressionPolicy(endpoint: endpoint, compressionMode: .highIntelligence)

        #expect(policy.effectiveCompactWindowTokens == 25_000)
        #expect(policy.autoCompactTokenLimit == 22_500)
    }

    @Test func test_standardMode_preserves_existing_40_percent_small_context_behavior() {
        let endpoint = TestHelpers.makeEndpoint(
            modelName: "gpt-4o-mini",
            maxContextTokens: 4096
        )

        let policy = CompressionPolicy(endpoint: endpoint, compressionMode: .standard)

        #expect(policy.promptTokenBudget == 1638)
        #expect(policy.autoCompactTokenLimit == 1638)
    }

    @Test func test_historyBudget_subtracts_fixed_tokens_from_selected_mode_limit() {
        let endpoint = TestHelpers.makeEndpoint(
            modelName: "deepseek-v4-pro",
            maxContextTokens: 100_000
        )

        let policy = CompressionPolicy(endpoint: endpoint, compressionMode: .highIntelligence)

        #expect(policy.historyBudget(fixedTokens: 500) == 22_000)
    }
}
