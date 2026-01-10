import MonadCore
import SwiftUI

public struct SidebarJobItem: View {
    let job: Job

    public init(job: Job) {
        self.job = job
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(job.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Spacer()

                // Priority badge
                Text("P\(job.priority)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(priorityColor(job.priority))
                    .cornerRadius(4)
            }

            if let description = job.description {
                Text(description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            // Status indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor(job.status))
                    .frame(width: 6, height: 6)
                Text(job.status.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(
            job.status == .inProgress ? Color.orange.opacity(0.05) : Color.secondary.opacity(0.05)
        )
        .cornerRadius(6)
    }

    private func priorityColor(_ priority: Int) -> Color {
        switch priority {
        case 8...10: return .red
        case 5...7: return .orange
        case 2...4: return .blue
        default: return .secondary
        }
    }

    private func statusColor(_ status: Job.Status) -> Color {
        switch status {
        case .pending: return .secondary
        case .inProgress: return .orange
        case .completed: return .green
        case .cancelled: return .gray
        }
    }
}
