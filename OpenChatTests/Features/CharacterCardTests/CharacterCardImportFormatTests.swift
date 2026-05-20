import Testing

@testable import OpenChat

@MainActor
@Suite("Character card import")
struct CharacterCardImportFormatTests {
    @Test func test_parse_openchat_format_maps_all_fields() throws {
        let parsed = try CharacterCardImportFormat.parse(text: """
        {
          "formatVersion": 1,
          "type": "openchat_character_card",
          "data": {
            "name": "Mira",
            "personality": "Careful.",
            "appearance": "Silver hair.",
            "physique": "Lean.",
            "speechStyle": "Quiet.",
            "backstory": "From the old district.",
            "systemPrompt": "Stay in character.",
            "scenario": "Rainy street.",
            "exampleDialogs": [
              {"role": "user", "content": "Hello"},
              {"role": "assistant", "content": "Stay close."}
            ],
            "creatorNotes": "Test card.",
            "tags": ["test", "noir"]
          }
        }
        """)

        #expect(parsed.name == "Mira")
        #expect(parsed.personality == "Careful.")
        #expect(parsed.appearance == "Silver hair.")
        #expect(parsed.physique == "Lean.")
        #expect(parsed.speechStyle == "Quiet.")
        #expect(parsed.backstory == "From the old district.")
        #expect(parsed.systemPrompt == "Stay in character.")
        #expect(parsed.scenario == "Rainy street.")
        #expect(parsed.exampleDialogs.count == 2)
        #expect(parsed.tags == ["noir", "test"])
        #expect(parsed.creatorNotes == "Test card.")
    }

    @Test func test_parse_sillytavern_v2_merges_description_personality_and_examples() throws {
        let parsed = try CharacterCardImportFormat.parse(text: """
        {
          "spec": "chara_card_v2",
          "spec_version": "2.0",
          "data": {
            "name": "Shiroko",
            "description": "A student moving through a ruined city.",
            "personality": "Quiet, direct, protective.",
            "scenario": "A night patrol.",
            "first_mes": "Stay behind me.",
            "mes_example": "<START>\\n{{user}}: Are you afraid?\\n{{char}}: Fear is data. I still move.\\n",
            "system_prompt": "Use restrained horror.",
            "creator_notes": "Imported from ST.",
            "tags": ["Blue Archive", "horror", "horror"]
          }
        }
        """)

        #expect(parsed.name == "Shiroko")
        #expect(parsed.personality == "A student moving through a ruined city.\n\nQuiet, direct, protective.")
        #expect(parsed.scenario == "A night patrol.")
        #expect(parsed.systemPrompt == "Use restrained horror.")
        #expect(parsed.creatorNotes == "Imported from ST.")
        #expect(parsed.tags == ["Blue Archive", "horror"])
        #expect(parsed.exampleDialogs.map(\.role) == ["assistant", "user", "assistant"])
        #expect(parsed.exampleDialogs.map(\.content) == [
            "Stay behind me.",
            "Are you afraid?",
            "Fear is data. I still move.",
        ])
    }

    @Test func test_import_card_persists_record_and_refreshes_list() async throws {
        let manager = try TestHelpers.makeDatabaseManager()
        let viewModel = CharacterCardListViewModel(
            databaseManager: manager,
            appState: AppState()
        )
        let parsed = CharacterCardImportFormat.ParsedCard(
            name: "Imported Shiroko",
            personality: "Quiet and alert.",
            appearance: nil,
            physique: nil,
            speechStyle: "Short sentences.",
            backstory: nil,
            systemPrompt: nil,
            scenario: "A ruined subway platform.",
            exampleDialogs: [ChatMessage(role: "assistant", content: "Keep moving.")],
            creatorNotes: nil,
            tags: ["BA", "horror"],
            warnings: []
        )

        let saved = try await viewModel.importCard(parsed)

        let fetched = try #require(try await manager.fetchCharacterCard(id: saved.id))
        #expect(fetched.name == "Imported Shiroko")
        #expect(fetched.personality == "Quiet and alert.")
        #expect(fetched.speechStyle == "Short sentences.")
        #expect(fetched.scenario == "A ruined subway platform.")
        #expect(fetched.decodedExampleDialogs == [ChatMessage(role: "assistant", content: "Keep moving.")])
        #expect(fetched.decodedTags == ["BA", "horror"])
        #expect(viewModel.cards.map(\.id) == [saved.id])
    }

    @Test func test_parse_missing_name_throws() {
        #expect(throws: CharacterCardImportError.missingName) {
            _ = try CharacterCardImportFormat.parse(text: """
            {
              "formatVersion": 1,
              "type": "openchat_character_card",
              "data": {
                "name": "   "
              }
            }
            """)
        }
    }

    @Test func test_parse_sillytavern_v2_warns_for_raw_example_lines() throws {
        let parsed = try CharacterCardImportFormat.parse(text: """
        {
          "spec": "chara_card_v2",
          "spec_version": "2.0",
          "data": {
            "name": "Raw Example",
            "mes_example": "<START>\\nUnlabeled line from an old card.\\n"
          }
        }
        """)

        #expect(parsed.exampleDialogs == [
            ChatMessage(role: "assistant", content: "Unlabeled line from an old card.")
        ])
        #expect(parsed.warnings.count == 1)
        #expect(parsed.warnings.first?.isEmpty == false)
    }
}
