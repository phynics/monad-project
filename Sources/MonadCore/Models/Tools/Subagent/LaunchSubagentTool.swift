import Foundation
import OpenAI

/// Tool to launch a focused subagent with specific documents
public struct LaunchSubagentTool: Tool, @unchecked Sendable {
    public let id = "launch_subagent"
    public let name = "Launch Subagent"
    public let description = "Launch a temporary subagent to process specific documents with a focused prompt. Use this for heavy processing of large files. IMPORTANT: Subagents cannot use tools; any information it needs must be provided in full via the 'documents' and 'prompt' parameters."
    public let requiresPermission = true
    
    public var usageExample: String? {
        """
        <tool_call>
        {\"name\": \"launch_subagent\", \"arguments\": {\"prompt\": \"Summarize these files\", \"documents\": [\"Sources/Main.swift\", \"README.md\"]}}
        </tool_call>
        """
    }
    
    private let llmService: LLMService
    private let documentManager: DocumentManager
    
    public init(llmService: LLMService, documentManager: DocumentManager) {
        self.llmService = llmService
        self.documentManager = documentManager
    }
    
    public func canExecute() async -> Bool {
        return await llmService.isConfigured
    }
    
    public var parametersSchema: [String: Any] {
        return [
            "type": "object",
            "properties": [
                "prompt": [
                    "type": "string",
                    "description": "The instruction for the subagent"
                ],
                "documents": [
                    "type": "array",
                    "items": [
                        "type": "string"
                    ],
                    "description": "List of file paths to load into the subagent's context"
                ]
            ],
            "required": ["prompt", "documents"]
        ]
    }
    
    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let prompt = parameters["prompt"] as? String,
              let docPaths = parameters["documents"] as? [String] else {
            let errorMsg = "Missing required parameters: prompt and documents."
            if let example = usageExample {
                return .failure("\(errorMsg) Example: \(example)")
            }
            return .failure(errorMsg)
        }
        
        // Gather documents
        var subagentDocs: [DocumentContext] = []
        for path in docPaths {
            // Check if already loaded
            if let existing = await documentManager.getDocument(path: path) {
                // Force full view for subagent
                var doc = existing
                doc.viewMode = .full
                subagentDocs.append(doc)
            } else {
                // Load from disk
                let url = URL(fileURLWithPath: path).standardized
                do {
                    let content = try String(contentsOf: url, encoding: .utf8)
                    let doc = DocumentContext(path: path, content: content, viewMode: .full)
                    subagentDocs.append(doc)
                } catch {
                    return .failure("Failed to load document '\(path)': \(error.localizedDescription)")
                }
            }
        }
        
        // Execute subagent call
        // We use chatStreamWithContext but with a fresh history and only these documents
        let (stream, _, _) = await llmService.chatStreamWithContext(
            userQuery: prompt,
            contextNotes: [], // Subagent starts fresh? Or should it inherit notes? Let's say fresh for "focused" task.
            documents: subagentDocs,
            memories: [],
            chatHistory: [],
            tools: [], // Subagent doesn't use tools for now (to avoid recursion depth issues)
            systemInstructions: "You are a focused subagent. You have been provided with specific documents to analyze. Answer the user's prompt based ONLY on these documents and your general knowledge. IMPORTANT: Be extremely brief and to the point. Provide only the facts and requested analysis without conversational filler.",
            useFastModel: true
        )
        
        var response = ""
        do {
            for try await result in stream {
                if let delta = result.choices.first?.delta.content {
                    response += delta
                }
            }
        } catch {
            return .failure("Subagent failed: \(error.localizedDescription)")
        }
        
        let context = SubagentContext(prompt: prompt, documents: docPaths, rawResponse: response)
        return .success("Subagent Output:\n\n\(response)", subagentContext: context)
    }
}
