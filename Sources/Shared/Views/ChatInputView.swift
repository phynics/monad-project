import SwiftUI

struct ChatInputView: View {
    @Binding var inputText: String
    let isLoading: Bool
    let isStreaming: Bool
    let llmServiceConfigured: Bool
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            TextField("Type a message...", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    onSend()
                }
                .disabled(isLoading || isStreaming || !llmServiceConfigured)

            if isStreaming {
                Button(action: onCancel) {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill")
                        Text("Cancel")
                    }
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            } else {
                Button("Send") {
                    onSend()
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputText.isEmpty || isLoading || !llmServiceConfigured)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.05))
    }
}
