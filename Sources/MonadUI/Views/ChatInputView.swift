import MonadCore
import SwiftUI

import MonadCore
import SwiftUI

struct ChatInputView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Active Context Bar (Memories & Documents)
            if !viewModel.activeMemories.isEmpty || !viewModel.documentManager.documents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Memories
                        ForEach(viewModel.activeMemories) { activeMemory in
                            HStack(spacing: 4) {
                                Image(systemName: "brain.head.profile")
                                    .foregroundColor(activeMemory.isPinned ? .orange : .purple)
                                Text(activeMemory.memory.title)
                                    .lineLimit(1)
                                
                                Button(action: { viewModel.toggleMemoryPin(id: activeMemory.id) }) {
                                    Image(systemName: activeMemory.isPinned ? "pin.fill" : "pin")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: { viewModel.removeActiveMemory(id: activeMemory.id) }) {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(activeMemory.isPinned ? Color.orange.opacity(0.1) : Color.purple.opacity(0.1))
                            .foregroundColor(activeMemory.isPinned ? .orange : .purple)
                            .cornerRadius(8)
                        }
                        
                        // Documents
                        ForEach(viewModel.documentManager.documents) { doc in
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text.fill")
                                    .foregroundColor(doc.isPinned ? .orange : .blue)
                                Text(URL(fileURLWithPath: doc.path).lastPathComponent)
                                    .lineLimit(1)
                                
                                if doc.viewMode == .excerpt {
                                    Text("(Excerpt)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                Button(action: { viewModel.documentManager.togglePin(path: doc.path) }) {
                                    Image(systemName: doc.isPinned ? "pin.fill" : "pin")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                                
                                Button(action: { viewModel.documentManager.unloadDocument(path: doc.path) }) {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                            }
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(doc.isPinned ? Color.orange.opacity(0.1) : Color.blue.opacity(0.1))
                            .foregroundColor(doc.isPinned ? .orange : .blue)
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color.gray.opacity(0.02))
                .overlay(Rectangle().frame(height: 1).foregroundColor(Color.gray.opacity(0.1)), alignment: .bottom)
            }
            
            HStack(spacing: 12) {
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
