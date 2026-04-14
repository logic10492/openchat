import Foundation

struct ModelParameters: Codable, Equatable, Sendable {
    var temperature: Double
    var topP: Double
    var maxTokens: Int?
    var frequencyPenalty: Double
    var presencePenalty: Double
    var stop: [String]?

    init(
        temperature: Double = 0.8,
        topP: Double = 1.0,
        maxTokens: Int? = nil,
        frequencyPenalty: Double = 0.0,
        presencePenalty: Double = 0.0,
        stop: [String]? = nil
    ) {
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.stop = stop
    }
}
