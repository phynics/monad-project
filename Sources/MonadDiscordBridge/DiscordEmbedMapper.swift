import Foundation
import DiscordBM
import MonadCore

struct DiscordEmbedMapper {
    static func mapMetadata(_ metadata: MonadChatResponse.Metadata) -> Embed {
        return Embed(
            title: "Response Metadata",
            color: .blue,
            footer: .init(text: "Monad Assistant"),
            fields: [
                .init(name: "Model", value: metadata.model, inline: true),
                .init(name: "Prompt Tokens", value: "\(metadata.promptTokens)", inline: true),
                .init(name: "Completion Tokens", value: "\(metadata.completionTokens)", inline: true)
            ]
        )
    }
    
    static func mapToolCall(_ toolCall: MonadToolCall) -> Embed {
        return Embed(
            title: "Tool Call: \(toolCall.name)",
            color: .orange,
            fields: [
                .init(name: "Arguments", value: "```json\n\(toolCall.argumentsJson)\n```")
            ]
        )
    }
    
    static func mapFinalMessage(_ message: MonadMessage) -> Embed? {
        guard !message.toolCalls.isEmpty else { return nil }
        
        let toolList = message.toolCalls.map { $0.name }.joined(separator: ", ")
        return Embed(
            title: "Tools Executed",
            description: toolList,
            color: .green
        )
    }
}

