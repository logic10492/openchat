import Foundation
import Testing

@testable import OpenChat

@Suite("ModelObject")
struct ModelObjectTests {
    @Test func test_model_object_decodes_context_length() throws {
        let json = """
        {"id": "llama-3", "object": "model", "owned_by": "meta", "context_length": 65536}
        """
        let data = Data(json.utf8)
        let model = try JSONDecoder().decode(ModelObject.self, from: data)
        #expect(model.id == "llama-3")
        #expect(model.contextLength == 65_536)
    }

    @Test func test_model_object_decodes_without_context_length() throws {
        let json = """
        {"id": "gpt-4o", "object": "model", "owned_by": "openai"}
        """
        let data = Data(json.utf8)
        let model = try JSONDecoder().decode(ModelObject.self, from: data)
        #expect(model.id == "gpt-4o")
        #expect(model.contextLength == nil)
    }

    @Test func test_endpoint_model_record_api_mode_value() {
        var record = EndpointModelRecord(
            id: "1",
            endpointId: "ep1",
            modelId: "test-model",
            maxContextTokens: 4096,
            apiMode: "chatCompletions",
            isDefault: true,
            isManual: false,
            createdAt: .now
        )
        #expect(record.apiModeValue == .chatCompletions)

        record.apiModeValue = .responses
        #expect(record.apiMode == "responses")
    }
}
