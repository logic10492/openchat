import SwiftUI

struct ModelParametersView: View {
    @State var viewModel: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LabeledContent(String(localized: "Temperature")) {
                Text(viewModel.defaultTemperature.formatted(.number.precision(.fractionLength(2))))
            }
            Slider(value: bind(\.defaultTemperature), in: 0...2, step: 0.05)

            LabeledContent(String(localized: "Top P")) {
                Text(viewModel.defaultTopP.formatted(.number.precision(.fractionLength(2))))
            }
            Slider(value: bind(\.defaultTopP), in: 0...1, step: 0.05)

            Stepper(value: maxTokensBinding, in: 128...16_384, step: 128) {
                Text("\(String(localized: "Max Tokens")): \(viewModel.defaultMaxTokens ?? 0)")
            }

            Picker(String(localized: "Context Strategy"), selection: contextBinding) {
                ForEach(ContextStrategy.allCases, id: \.rawValue) { strategy in
                    Text(strategy.rawValue.capitalized).tag(strategy)
                }
            }

            Button(String(localized: "Restore Defaults")) {
                viewModel.resetModelParameters()
            }
        }
        .onDisappear {
            viewModel.persistDefaults()
        }
    }

    private func bind(_ keyPath: ReferenceWritableKeyPath<SettingsViewModel, Double>) -> Binding<Double> {
        @Bindable var viewModel = viewModel
        return Binding(
            get: { viewModel[keyPath: keyPath] },
            set: {
                viewModel[keyPath: keyPath] = $0
                viewModel.persistDefaults()
            }
        )
    }

    private var maxTokensBinding: Binding<Int> {
        Binding(
            get: { viewModel.defaultMaxTokens ?? 1024 },
            set: {
                viewModel.defaultMaxTokens = $0
                viewModel.persistDefaults()
            }
        )
    }

    private var contextBinding: Binding<ContextStrategy> {
        Binding(
            get: { viewModel.defaultContextStrategy },
            set: {
                viewModel.defaultContextStrategy = $0
                viewModel.persistDefaults()
            }
        )
    }
}
