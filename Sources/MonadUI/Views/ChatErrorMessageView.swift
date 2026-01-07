import MonadCore
import SwiftUI

struct ChatErrorMessageView: View {
    @Binding var errorMessage: String?
    let onRetry: () -> Void

    var body: some View {
        if let error = errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: onRetry) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption.bold())
                    .foregroundColor(.blue)

                    Button("Dismiss") {
                        errorMessage = nil
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.1))
        }
    }
}
