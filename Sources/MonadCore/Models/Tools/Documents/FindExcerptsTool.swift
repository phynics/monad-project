import Foundation

/// Tool to launch a specialized subagent to find excerpts within a document
public struct FindExcerptsTool: Tool, Sendable {
    public let id = "find_excerpts"
    public let name = "Find Excerpts"
    public let description =
        "Launch a specialized subagent to scan a document and find specific information. It returns a list of recommended offsets and lengths that you can use with `switch_document_view` in `excerpt` mode."
    public let requiresPermission = false

    public var usageExample: String? {
        """
        <tool_call>
        {\"name\": \"find_excerpts\", \"arguments\": {\"path\": \"Sources/Main.swift\", \"search_instruction\": \"Find where the network configuration is initialized\"}}
        </tool_call>
        """
    }

    private let llmService: any LLMServiceProtocol
    private let documentManager: DocumentManager

    public init(llmService: any LLMServiceProtocol, documentManager: DocumentManager) {
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
                "path": [
                    "type": "string",
                    "description": "Path to the loaded document to scan",
                ],
                "search_instruction": [
                    "type": "string",
                    "description":
                        "Describe what specific information or code section you are looking for",
                ],
            ],
            "required": ["path", "search_instruction"],
        ]
    }

    public func execute(parameters: [String: Any]) async throws -> ToolResult {
        guard let path = parameters["path"] as? String,
            let instruction = parameters["search_instruction"] as? String
        else {
            return .failure("Missing required parameters: path, search_instruction.")
        }

        guard let doc = await documentManager.getDocument(path: path) else {
            return .failure("Document not found in context: \(path). Load it first.")
        }

        // We prompt the subagent to find character offsets
        let subagentPrompt = """
            I am looking for the following in the document '\(path)':
            "\(instruction)"

            Analyze the provided document and find 1-3 relevant excerpts.
            For each excerpt, provide:
            1. A brief description of what was found.
            2. The character offset (0-based) where the excerpt starts.
            3. The length of the excerpt in characters.

            Return your findings in a clear list.
            """

        // Create a copy of the doc in raw mode for the subagent
        var rawDoc = doc
        rawDoc.viewMode = .raw

        let (stream, _, _) = await llmService.chatStreamWithContext(
            userQuery: subagentPrompt,
            contextNotes: [],
            documents: [rawDoc],
            memories: [],
            chatHistory: [],
            tools: [],
            systemInstructions:
                "You are a document scanner subagent. Your goal is to find specific information in a document and report its exact character offset and length. Be precise.",
            responseFormat: nil,
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

        let context = SubagentContext(
            prompt: subagentPrompt, documents: [path], rawResponse: response)
        return .success(
            "Subagent Findings for '\(instruction)':\n\n\(response)\n\nUse `switch_document_view` with mode `excerpt` and the provided offset/length to read these sections.",
            subagentContext: context)
    }
}