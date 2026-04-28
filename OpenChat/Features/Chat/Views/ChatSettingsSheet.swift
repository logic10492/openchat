import SwiftUI

struct ChatSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: ChatViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "Conversation")) {
                    Picker(String(localized: "Endpoint"), selection: endpointBinding) {
                        Text(String(localized: "Use Default")).tag(Optional<String>.none)
                        ForEach(viewModel.availableEndpoints) { endpoint in
                            Text(endpoint.name).tag(Optional(endpoint.id))
                        }
                    }
                    .onChange(of: viewModel.selectedEndpointID) {
                        viewModel.selectedModelName = nil
                        Task { await viewModel.loadModelsForEndpoint() }
                    }

                    Picker(String(localized: "Model"), selection: modelBinding) {
                        Text(String(localized: "Use Default")).tag(Optional<String>.none)
                        ForEach(viewModel.availableModelsForEndpoint) { model in
                            Text(model.modelId).tag(Optional(model.modelId))
                        }
                    }

                    Picker(String(localized: "Character"), selection: characterBinding) {
                        Text(String(localized: "None")).tag(Optional<String>.none)
                        ForEach(viewModel.availableCharacterCards) { card in
                            Text(card.name).tag(Optional(card.id))
                        }
                    }

                    if let worldBookName = viewModel.selectedCharacterWorldBookName {
                        LabeledContent(String(localized: "World Book")) {
                            Text(worldBookName)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker(String(localized: "Context Strategy"), selection: strategyBinding) {
                        ForEach(ContextStrategy.allCases, id: \.rawValue) { strategy in
                            Text(LocalizedStringKey(strategy.rawValue.capitalized)).tag(strategy)
                        }
                    }

                    TextField(String(localized: "Custom Scenario"), text: scenarioBinding, axis: .vertical)

                    Toggle(String(localized: "Slow Plot Progression (Beta)"), isOn: slowPlotModeBinding)
                }

                Section(String(localized: "Model")) {
                    LabeledContent(String(localized: "Temperature")) {
                        Text(viewModel.modelTemperature.formatted(.number.precision(.fractionLength(2))))
                    }
                    Slider(value: temperatureBinding, in: 0...2, step: 0.05)

                    LabeledContent(String(localized: "Top P")) {
                        Text(viewModel.modelTopP.formatted(.number.precision(.fractionLength(2))))
                    }
                    Slider(value: topPBinding, in: 0...1, step: 0.05)

                    Stepper(value: maxTokensBinding, in: 128...131_072, step: 128) {
                        Text("\(String(localized: "Max Tokens")): \(viewModel.modelMaxTokens)")
                    }

                    Toggle(String(localized: "Enable Thinking"), isOn: thinkingEnabledBinding)

                    if viewModel.thinkingEnabled {
                        if viewModel.selectedProviderDialect == .deepSeekV4 {
                            Picker(String(localized: "Reasoning Effort"), selection: reasoningEffortBinding) {
                                ForEach(ReasoningEffort.allCases) { effort in
                                    Text(effort.displayName).tag(effort)
                                }
                            }
                        } else {
                            Stepper(value: thinkingBudgetBinding, in: 1024...65_536, step: 1024) {
                                Text("\(String(localized: "Thinking Budget")): \(viewModel.thinkingBudget)")
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Chat Settings"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done")) {
                        Task {
                            await viewModel.saveConversationSettings()
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var endpointBinding: Binding<String?> {
        @Bindable var viewModel = viewModel
        return $viewModel.selectedEndpointID
    }

    private var modelBinding: Binding<String?> {
        @Bindable var viewModel = viewModel
        return $viewModel.selectedModelName
    }

    private var characterBinding: Binding<String?> {
        @Bindable var viewModel = viewModel
        return $viewModel.selectedCharacterCardID
    }

    private var strategyBinding: Binding<ContextStrategy> {
        @Bindable var viewModel = viewModel
        return $viewModel.selectedContextStrategy
    }

    private var scenarioBinding: Binding<String> {
        @Bindable var viewModel = viewModel
        return $viewModel.customScenario
    }

    private var slowPlotModeBinding: Binding<Bool> {
        @Bindable var viewModel = viewModel
        return $viewModel.slowPlotMode
    }

    private var temperatureBinding: Binding<Double> {
        @Bindable var viewModel = viewModel
        return $viewModel.modelTemperature
    }

    private var topPBinding: Binding<Double> {
        @Bindable var viewModel = viewModel
        return $viewModel.modelTopP
    }

    private var maxTokensBinding: Binding<Int> {
        @Bindable var viewModel = viewModel
        return $viewModel.modelMaxTokens
    }

    private var thinkingEnabledBinding: Binding<Bool> {
        @Bindable var viewModel = viewModel
        return $viewModel.thinkingEnabled
    }

    private var thinkingBudgetBinding: Binding<Int> {
        @Bindable var viewModel = viewModel
        return $viewModel.thinkingBudget
    }

    private var reasoningEffortBinding: Binding<ReasoningEffort> {
        @Bindable var viewModel = viewModel
        return $viewModel.reasoningEffort
    }
}
