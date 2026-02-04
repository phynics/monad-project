import Foundation
import ArgumentParser
import MonadClient
import MonadCore

struct CLISessionManager {
    let client: MonadClient
    
    /// Resolves which session to use (Resume or New)
    func resolveSession(
        explicitId: String?, 
        persona: String?,
        localConfig: LocalConfig
    ) async throws -> Session {
        
        // 1. Try to resume from flag
        if let sessionId = explicitId, let uuid = UUID(uuidString: sessionId) {
            do {
                _ = try await client.getHistory(sessionId: uuid)
                TerminalUI.printInfo("Resuming session \(uuid.uuidString.prefix(8))...")
                return Session(id: uuid, title: nil)
            } catch {
                TerminalUI.printError("Session not found: \(sessionId)")
                throw ExitCode.failure
            }
        }
        
        // 2. Try to resume from config (automatic)
        if let lastId = localConfig.lastSessionId, let uuid = UUID(uuidString: lastId) {
            do {
                _ = try await client.getHistory(sessionId: uuid)
                TerminalUI.printInfo("Resumed session \(uuid.uuidString.prefix(8))")
                return Session(id: uuid, title: nil)
            } catch {
                // Stale config, ignore and proceed to menu
            }
        }
        
        // 3. Interactive Menu
        return try await showSessionMenu(persona: persona)
    }
    
    private func showSessionMenu(persona: String?) async throws -> Session {
        print("")
        print(TerminalUI.bold("No active session found."))
        print("  [1] Create New Session")
        print("  [2] List Existing Sessions")
        print("")
        print("Select an option [1]: ", terminator: "")
        
        let choice = readLine()?.trimmingCharacters(in: .whitespaces) ?? "1"
        
        if choice == "2" {
            let sessions = try await client.listSessions()
            if sessions.isEmpty {
                print("No sessions found. Creating new one.")
                return try await createNewSessionFlow(persona: persona)
            }
            
            print("")
            for (i, s) in sessions.enumerated() {
                let title = s.title ?? "Untitled"
                let date = TerminalUI.formatDate(s.updatedAt)
                print("  [\(i+1)] \(title) (\(s.id.uuidString.prefix(8))) - \(date)")
            }
            print("")
            print("Select a session [1]: ", terminator: "")
            let indexStr = readLine()?.trimmingCharacters(in: .whitespaces) ?? "1"
            let index = (Int(indexStr) ?? 1) - 1
            
            if index >= 0 && index < sessions.count {
                let s = sessions[index]
                return Session(id: s.id, title: s.title)
            } else {
                TerminalUI.printError("Invalid selection.")
                throw ExitCode.failure
            }
        } else {
            return try await createNewSessionFlow(persona: persona)
        }
    }
    
    private func createNewSessionFlow(persona: String?) async throws -> Session {
        var selectedPersona = persona
        
        if selectedPersona == nil {
            let personas = try await client.listPersonas()
            print("")
            print(TerminalUI.bold("Select a Persona:"))
            for (i, p) in personas.enumerated() {
                print("  [\(i+1)] \(p.id)")
            }
            print("")
            print("Select [1]: ", terminator: "")
            let choice = readLine()?.trimmingCharacters(in: .whitespaces) ?? "1"
            let index = (Int(choice) ?? 1) - 1
            if index >= 0 && index < personas.count {
                selectedPersona = personas[index].id
            } else {
                selectedPersona = "Default.md"
            }
        }
        
        let session = try await client.createSession(persona: selectedPersona)
        TerminalUI.printSuccess("Created new session \(session.id.uuidString.prefix(8)) with persona \(selectedPersona!)")
        return session
    }
    
    /// Handles re-attachment of client-side workspaces
    func handleWorkspaceReattachment(session: Session, localConfig: LocalConfig) async {
        guard let workspaces = localConfig.clientWorkspaces, !workspaces.isEmpty else { return }
        
        print("")
        TerminalUI.printInfo("Found previously attached client-side workspaces:")
        
        for (uri, _) in workspaces {
            print("  - \(uri)")
        }
        
        print("")
        print("Re-attach these workspaces? (y/n) [y]: ", terminator: "")
        let response = readLine()?.lowercased().trimmingCharacters(in: .whitespaces) ?? "y"
        
        if response == "y" || response == "" {
            for (uri, wsIdStr) in workspaces {
                guard let wsId = UUID(uuidString: wsIdStr) else { continue }
                
                do {
                    // Verify workspace exists on server and is linked to this client
                    // Actually, we can just attempt to attach. If it fails, it might be gone.
                    try await client.attachWorkspace(wsId, to: session.id, isPrimary: false)
                    TerminalUI.printSuccess("Attached \(uri)")
                } catch {
                    TerminalUI.printError("Failed to re-attach \(uri): \(error.localizedDescription)")
                }
            }
        }
    }
}
