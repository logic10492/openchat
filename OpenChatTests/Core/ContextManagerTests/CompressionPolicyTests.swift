import Testing

@testable import OpenChat

@Suite("Compression policy")
struct CompressionPolicyTests {
    @Test func test_gpt55_uses_codex_effective_compact_window() {
        let endpoint = TestHelpers.makeEndpoint(
            modelName: "gpt-5.5",
            maxContextTokens: 1_024_000
        )

        let policy = CompressionPolicy(endpoint: endpoint)

        #expect(policy.effectiveCompactWindowTokens == 258_000)
        #expect(policy.autoCompactTokenLimit == 232_200)
    }

    @Test func test_autoCompactLimit_respects_openchat_40_percent_cap() {
        let endpoint = TestHelpers.makeEndpoint(
            modelName: "gpt-4o-mini",
            maxContextTokens: 4096
        )

        let policy = CompressionPolicy(endpoint: endpoint)

        #expect(policy.promptTokenBudget == 1638)
        #expect(policy.autoCompactTokenLimit == 1638)
    }

    @Test func test_large_non_gpt55_model_uses_40_percent_prompt_budget_when_lower() {
        let endpoint = TestHelpers.makeEndpoint(
            modelName: "deepseek-v4-pro",
            maxContextTokens: 1_000_000
        )

        let policy = CompressionPolicy(endpoint: endpoint)

        #expect(policy.effectiveCompactWindowTokens == 1_000_000)
        #expect(policy.autoCompactTokenLimit == 400_000)
    }
}
