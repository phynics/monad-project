import MonadCore
import SwiftUI

struct MessageDebugInfoView: View {
    let message: Message
    
    var body: some View {
        Section {
            InfoRow(label: "Role", value: message.role.rawValue.capitalized)
            InfoRow(label: "Timestamp", value: message.timestamp.formatted())
            if let think = message.think {
                InfoRow(label: "Has Thinking", value: "Yes (\(think.count) chars)")
            }
        } header: {
            SectionHeader(title: "Message Info")
        }
    }
}
