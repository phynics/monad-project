import Foundation
import MonadShared
import GRDB

/// Represents an agent definition in the system, consisting of instructions and prompts.
public struct Agent: Codable, Sendable, Identifiable, Equatable {
    /// Unique identifier for the agent (e.g. "default", "coder")
    public let id: UUID 
    
    /// Display name of the agent
    public var name: String
    
    /// Description of the agent's purpose
    public var description: String
    
    /// The core instructions for the agent
    public var systemPrompt: String
    
    /// Optional: Adds tone, voice, and personality
    public var personaPrompt: String?
    
    /// Optional: Behavioral constraints and safety rules
    public var guardrailsPrompt: String?
    
    /// Timestamp when the agent was created
    public let createdAt: Date
    
    /// Timestamp when the agent was last updated
    public var updatedAt: Date

    public init(
        id: UUID,
        name: String,
        description: String,
        systemPrompt: String,
        personaPrompt: String? = nil,
        guardrailsPrompt: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.systemPrompt = systemPrompt
        self.personaPrompt = personaPrompt
        self.guardrailsPrompt = guardrailsPrompt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Agent {
    /// Composed full system instructions for the LLM
    public var composedInstructions: String {
        var parts = [systemPrompt]
        
        if let persona = personaPrompt, !persona.isEmpty {
            parts.append("## Persona\n" + persona)
        }
        
        if let guardrails = guardrailsPrompt, !guardrails.isEmpty {
            parts.append("## Guardrails\n" + guardrails)
        }
        
        return parts.joined(separator: "\n\n")
    }
}

// MARK: - Persistence Extensions for Agent

extension Agent: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "agent" }
}

extension Agent {
    /// Helper to fetch the default agent from the database
    public static func fetchDefault(in db: Database) throws -> Agent? {
        try Agent.fetchOne(db, key: "default")
    }
}