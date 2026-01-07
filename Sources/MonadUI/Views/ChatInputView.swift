import MonadCore
import SwiftUI

struct ChatInputView: View {
    @Binding var inputText: String
    let isLoading: Bool
    let isStreaming: Bool
    let llmServiceConfigured: Bool
    let documentManager: DocumentManager?
    let onSend: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Document List Bling
            if let manager = documentManager, !manager.documents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(manager.documents) { doc in
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text.fill")
                                Text(URL(fileURLWithPath: doc.path).lastPathComponent)
                                    .lineLimit(1)
                                if doc.viewMode == .excerpt {
                                    Text("(Excerpt)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
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
                    .disabled(inputText.isEmpty || isLoading || isStreaming || !llmServiceConfigured)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.05))
        }
    }
}
