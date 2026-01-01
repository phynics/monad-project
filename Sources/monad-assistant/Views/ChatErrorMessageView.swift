import SwiftUI

struct ChatErrorMessageView: View {
    @Binding var errorMessage: String?

    var body: some View {
        if let error = errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Dismiss") {
                    errorMessage = nil
                }
                .buttonStyle(.plain)
                .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.1))
        }
    }
}
