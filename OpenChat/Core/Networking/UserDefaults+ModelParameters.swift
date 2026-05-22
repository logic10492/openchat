import Foundation

extension UserDefaults {
    func openChatDefaultModelParameters() -> ModelParameters {
        ModelParameters(
            temperature: object(forKey: "default_temperature") == nil
                ? ModelParameters.openChatDefaultTemperature
                : double(forKey: "default_temperature"),
            topP: object(forKey: "default_top_p") == nil
                ? ModelParameters.openChatDefaultTopP
                : double(forKey: "default_top_p"),
            maxTokens: object(forKey: "default_max_tokens") == nil
                ? nil
                : integer(forKey: "default_max_tokens"),
            frequencyPenalty: object(forKey: "default_frequency_penalty") == nil
                ? 0
                : double(forKey: "default_frequency_penalty"),
            presencePenalty: object(forKey: "default_presence_penalty") == nil
                ? 0
                : double(forKey: "default_presence_penalty"),
            stop: nil
        )
    }
}
