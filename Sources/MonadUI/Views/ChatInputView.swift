import MonadCore
import SwiftUI

import MonadCore
import SwiftUI

struct ChatInputView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // ... (rest of the body)
                TextField("Type a message...", text: $viewModel.inputText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        viewModel.sendMessage()
                    }
                    .disabled(viewModel.isLoading || viewModel.isStreaming || !viewModel.llmService.isConfigured)

                if viewModel.isStreaming {
                    Button(action: viewModel.cancelGeneration) {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                            Text("Cancel")
                        }
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                } else {
                    Button("Send") {
                        viewModel.sendMessage()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.inputText.isEmpty || viewModel.isLoading || viewModel.isStreaming || !viewModel.llmService.isConfigured)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
        }
    }
}
