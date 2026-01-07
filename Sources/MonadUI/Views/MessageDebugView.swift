import MonadCore
import SwiftUI

#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Simple debug view for message details
struct MessageDebugView: View {
    let message: Message
    let debugInfo: MessageDebugInfo
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    
                    MessageDebugInfoView(message: message)

                    Divider()

                    if debugInfo.rawPrompt != nil || debugInfo.structuredContext != nil {
                        MessageDebugPromptContextView(debugInfo: debugInfo)
                        Divider()
                    }
                    
                    if message.role == .user {
                        MessageDebugContextPipelineView(debugInfo: debugInfo)
                        Divider()
                    }

                    MessageDebugResponseView(debugInfo: debugInfo)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Message Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
            .frame(minWidth: 600, minHeight: 500)
        #endif
    }
}