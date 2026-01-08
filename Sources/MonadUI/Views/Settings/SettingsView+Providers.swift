import SwiftUI
import MonadCore

extension SettingsView {
    @ViewBuilder
    internal var providerSettings: some View {
        switch provider {
        case .openAI:
            openAISettings
        case .openRouter:
            openRouterSettings
        case .openAICompatible:
            openAICompatibleSettings
        case .ollama:
            ollamaSettings
        }
    }
    
    @ViewBuilder
    private var openRouterSettings: some View {
        LabeledContent("API Key") {
            SecureField("OpenRouter API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
        }

        LabeledContent("API Endpoint") {
            HStack {
                TextField("https://openrouter.ai/api", text: $endpoint)
                    .textFieldStyle(.roundedBorder)
                
                Button {
                    fetchOpenRouterModels()
                } label: {
                    if isFetchingModels {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Fetch Models")
                    }
                }
                .disabled(isFetchingModels || endpoint.isEmpty || apiKey.isEmpty)
            }
        }

        Group {
            openRouterModelPicker("Model Name (Main)", selection: $modelName)
            openRouterModelPicker("Utility Model", selection: $utilityModel)
            openRouterModelPicker("Fast Model", selection: $fastModel)
        }
    }

    @ViewBuilder
    private func openRouterModelPicker(_ label: String, selection: Binding<String>) -> some View {
        LabeledContent(label) {
            HStack {
                if openAIModels.isEmpty {
                    TextField("e.g. anthropic/claude-3.5-sonnet", text: selection)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker("", selection: selection) {
                        ForEach(openAIModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }
                openRouterModelMenu(binding: selection)
            }
        }
    }

    private func openRouterModelMenu(binding: Binding<String>) -> some View {
        Menu {
            Button("anthropic/claude-3.5-sonnet") { binding.wrappedValue = "anthropic/claude-3.5-sonnet" }
            Button("anthropic/claude-3-haiku") { binding.wrappedValue = "anthropic/claude-3-haiku" }
            Button("openai/gpt-4o") { binding.wrappedValue = "openai/gpt-4o" }
            Button("openai/gpt-4o-mini") { binding.wrappedValue = "openai/gpt-4o-mini" }
            Button("google/gemini-pro-1.5") { binding.wrappedValue = "google/gemini-pro-1.5" }
            Button("google/gemini-flash-1.5") { binding.wrappedValue = "google/gemini-flash-1.5" }
            Button("meta-llama/llama-3.1-405b-instruct") { binding.wrappedValue = "meta-llama/llama-3.1-405b-instruct" }
            Button("meta-llama/llama-3.1-70b-instruct") { binding.wrappedValue = "meta-llama/llama-3.1-70b-instruct" }
        } label: {
            Image(systemName: "chevron.down.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private var openAISettings: some View {
        Group {
            LabeledContent("Model Name (Main)") {
                HStack {
                    TextField("gpt-4o", text: $modelName)
                        .textFieldStyle(.roundedBorder)
                    modelMenu(binding: $modelName)
                }
            }
            
            LabeledContent("Utility Model") {
                HStack {
                    TextField("gpt-4o-mini", text: $utilityModel)
                        .textFieldStyle(.roundedBorder)
                    modelMenu(binding: $utilityModel)
                }
            }
            
            LabeledContent("Fast Model") {
                HStack {
                    TextField("gpt-4o-mini", text: $fastModel)
                        .textFieldStyle(.roundedBorder)
                    modelMenu(binding: $fastModel)
                }
            }
        }

        LabeledContent("API Key") {
            SecureField("", text: $apiKey)
                .textFieldStyle(.roundedBorder)
        }

        LabeledContent("API Endpoint") {
            TextField("", text: $endpoint)
                .textFieldStyle(.roundedBorder)
                .foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private var openAICompatibleSettings: some View {
        LabeledContent("API Endpoint") {
            HStack {
                TextField("", text: $endpoint)
                    .textFieldStyle(.roundedBorder)

                Button {
                    fetchOpenAIModels()
                } label: {
                    if isFetchingModels {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Fetch Models")
                    }
                }
                .disabled(isFetchingModels || endpoint.isEmpty || apiKey.isEmpty)
            }
        }

        LabeledContent("API Key") {
            SecureField("Required", text: $apiKey)
                .textFieldStyle(.roundedBorder)
        }

        Group {
            openAIModelPicker("Model Name", selection: $modelName)
            openAIModelPicker("Utility Model", selection: $utilityModel)
            openAIModelPicker("Fast Model", selection: $fastModel)
        }
    }
    
    @ViewBuilder
    private var ollamaSettings: some View {
        LabeledContent("API Endpoint") {
            HStack {
                TextField("", text: $endpoint)
                    .textFieldStyle(.roundedBorder)

                Button {
                    fetchOllamaModels()
                } label: {
                    if isFetchingModels {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Fetch Models")
                    }
                }
                .disabled(isFetchingModels || endpoint.isEmpty)
            }
        }

        Group {
            ollamaModelPicker("Model Name (Main)", selection: $modelName)
            ollamaModelPicker("Utility Model", selection: $utilityModel)
            ollamaModelPicker("Fast Model", selection: $fastModel)
        }
    }
    
    internal func modelMenu(binding: Binding<String>) -> some View {
        Menu {
            Button("gpt-4o") { binding.wrappedValue = "gpt-4o" }
            Button("gpt-4o-mini") { binding.wrappedValue = "gpt-4o-mini" }
            Button("gpt-4-turbo") { binding.wrappedValue = "gpt-4-turbo" }
            Button("gpt-3.5-turbo") { binding.wrappedValue = "gpt-3.5-turbo" }
        } label: {
            Image(systemName: "chevron.down.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
    
    @ViewBuilder
    internal func ollamaModelPicker(_ label: String, selection: Binding<String>) -> some View {
        LabeledContent(label) {
            if ollamaModels.isEmpty {
                TextField("", text: selection)
                    .textFieldStyle(.roundedBorder)
            } else {
                Picker("", selection: selection) {
                    ForEach(ollamaModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
            }
        }
    }

    @ViewBuilder
    internal func openAIModelPicker(_ label: String, selection: Binding<String>) -> some View {
        LabeledContent(label) {
            if openAIModels.isEmpty {
                TextField("", text: selection)
                    .textFieldStyle(.roundedBorder)
            } else {
                Picker("", selection: selection) {
                    ForEach(openAIModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
            }
        }
    }
}
