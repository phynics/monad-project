import Foundation
import MonadClient
import MonadShared

// Needed for fflush
#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

extension ChatREPL {
    func getContextSummary() async -> String {
        // Quick health check — short-circuit if server is down
        let serverOnline: Bool
        do {
            serverOnline = try await client.healthCheck()
        } catch {
            serverOnline = false
        }
        lastServerStatus = serverOnline

        guard serverOnline else {
            return TerminalUI.red("✗ Server offline")
                + "  "
                + TerminalUI.dim("— /status to check, Ctrl-C to exit")
        }

        do {
            let timelineWS = try await client.workspace.listTimelineWorkspaces(timelineId: timeline.id)
            var wsSummary = "No Workspace"

            let displayId = selectedWorkspaceId ?? timelineWS.primary?.id

            if let targetId = displayId {
                do {
                    let workspace = try await client.workspace.getWorkspace(targetId)
                    let icon = selectedWorkspaceId == nil ? "📂" : "🎯"
                    wsSummary = "\(icon) \(workspace.uri.description)"

                    if selectedWorkspaceId == nil && !timelineWS.attached.isEmpty {
                        wsSummary += " (+\(timelineWS.attached.count) attached)"
                    }
                } catch {
                    logger.warning("Could not fetch workspace details for \(targetId): \(error)")
                    wsSummary = "📂 [Workspace error]"
                }
            }

            var activeCountString = ""
            do {
                let config = try await client.getConfiguration()
                let memories = try await client.chat.listMemories()
                let activeCount = min(memories.count, config.memoryContextLimit)
                activeCountString = " | 🧠 \(activeCount) active memories"
            } catch {
                logger.warning("Could not fetch memory context: \(error)")
                activeCountString = " | 🧠 [Memory error]"
            }

            return "\(wsSummary)\(activeCountString)"
        } catch {
            logger.error("Context summary failed: \(error)")
            return TerminalUI.yellow("⚠️ Context unavailable")
        }
    }

    func showContext() async {
        do {
            let memories: [Memory]
            do {
                memories = try await client.chat.listMemories()
            } catch {
                logger.warning("Could not fetch memories: \(error)")
                memories = []
            }

            let config = try await client.getConfiguration()

            print(TerminalUI.dim("─────────────────────────────────────────"))

            let providerName = config.activeProvider.rawValue
            print(TerminalUI.dim("🤖 Provider: \(providerName)"))
            print(TerminalUI.dim("   Main:    \(config.modelName)"))
            if !config.utilityModel.isEmpty {
                print(TerminalUI.dim("   Utility: \(config.utilityModel)"))
            }
            if !config.fastModel.isEmpty, config.fastModel != config.utilityModel {
                print(TerminalUI.dim("   Fast:    \(config.fastModel)"))
            }

            if !memories.isEmpty {
                let limit = config.memoryContextLimit
                let activeCount = min(memories.count, limit)
                print(TerminalUI.dim("📚 \(activeCount) memories active (of \(memories.count) total)"))
            }

            if config.documentContextLimit > 0 {
                print(TerminalUI.dim("📄 Document context: \(config.documentContextLimit) max"))
            }

            print(TerminalUI.dim("─────────────────────────────────────────"))
            print("")
        } catch {
            logger.error("Could not load context configuration: \(error)")
            TerminalUI.printWarning("Could not load context: \(error.localizedDescription)")
        }
    }

    func checkAndRestoreWorkspaces() async {
        do {
            let timelineWS = try await client.workspace.listTimelineWorkspaces(timelineId: timeline.id)
            let workspacesToRestore = collectMissingWorkspaces(from: timelineWS)

            guard !workspacesToRestore.isEmpty else { return }

            printMissingWorkspacesSummary(workspacesToRestore)

            if let input = lineReader.readLine(prompt: "", completion: nil)?
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), input == "y" {
                await restoreWorkspaces(workspacesToRestore)
            } else {
                print("Skipping restoration.")
            }
            print(TerminalUI.dim("------------------------------------------------"))
            print("")

        } catch {
            // Ignore errors here to not block startup, but log them
            logger.error("Workspace restoration check failed: \(error)")
        }
    }

    private func collectMissingWorkspaces(
        from timelineWS: (primary: WorkspaceReference?, attached: [WorkspaceReference])
    ) -> [WorkspaceReference] {
        var workspacesToRestore: [WorkspaceReference] = []

        if let primary = timelineWS.primary, primary.status == .missing, primary.hostType == .server {
            workspacesToRestore.append(primary)
        }

        if let identity = RegistrationManager.shared.getIdentity() {
            for workspace in timelineWS.attached {
                if workspace.hostType == .client, workspace.ownerId == identity.clientId {
                    if let url = URL(string: workspace.uri.description), url.host == identity.hostname {
                        let path = url.path
                        if !FileManager.default.fileExists(atPath: path) {
                            workspacesToRestore.append(workspace)
                        } else {
                            LocalConfigManager.shared.saveClientWorkspace(
                                uri: workspace.uri.description, id: workspace.id.uuidString
                            )
                        }
                    }
                }
            }
        }

        return workspacesToRestore
    }

    private func printMissingWorkspacesSummary(_ workspacesToRestore: [WorkspaceReference]) {
        print(TerminalUI.dim("------------------------------------------------"))
        TerminalUI.printWarning("Missing Workspaces Detected:")
        for workspace in workspacesToRestore {
            print(" - \(workspace.uri.description) (\(workspace.hostType == .server ? "Server" : "Client"))")
        }
        print("")
        print("Do you want to restore these workspaces? [y/N] ", terminator: "")
        fflush(stdout)
    }

    private func restoreWorkspaces(_ workspacesToRestore: [WorkspaceReference]) async {
        for workspace in workspacesToRestore {
            do {
                if workspace.hostType == .server {
                    try await client.workspace.restoreWorkspace(
                        timelineId: timeline.id, workspaceId: workspace.id
                    )
                    TerminalUI.printSuccess("Restored server workspace: \(workspace.uri.description)")
                } else {
                    if let url = URL(string: workspace.uri.description) {
                        try FileManager.default.createDirectory(
                            at: url, withIntermediateDirectories: true
                        )
                        TerminalUI.printSuccess("Created local directory: \(url.path)")
                    }
                }
            } catch {
                logger.error("Failed to restore workspace \(workspace.uri.description): \(error)")
                TerminalUI.printError(
                    "Could not restore \(workspace.uri.description): \(error.localizedDescription)"
                )
            }
        }
    }

    func autoAttachCurrentDirectory() async {
        do {
            let pwd = FileManager.default.currentDirectoryPath
            let hostname = ProcessInfo.processInfo.hostName
            let uriString = WorkspaceURI.clientProject(hostname: hostname, path: pwd).description

            guard let myId = RegistrationManager.shared.getIdentity()?.clientId else { return }

            let allWorkspaces = try await client.workspace.listWorkspaces()
            var targetWorkspaceId: UUID?

            if let existing = allWorkspaces.first(where: { $0.uri.description == uriString }) {
                targetWorkspaceId = existing.id
            } else {
                guard let uri = WorkspaceURI(parsing: uriString) else { return }
                let newWs = try await client.workspace.createWorkspace(
                    uri: uri,
                    hostType: .client,
                    ownerId: myId,
                    rootPath: pwd,
                    trustLevel: .readOnly
                )
                targetWorkspaceId = newWs.id
            }

            if let wsId = targetWorkspaceId {
                let timelineWS = try await client.workspace.listTimelineWorkspaces(timelineId: timeline.id)
                let isAttached = timelineWS.attached.contains { $0.id == wsId }

                if !isAttached {
                    try await client.workspace.attachWorkspace(wsId, to: timeline.id)
                }

                try await client.workspace.syncWorkspaceTools(
                    ClientConstants.readOnlyToolReferences, workspaceId: wsId
                )

                LocalConfigManager.shared.saveClientWorkspace(uri: uriString, id: wsId.uuidString)
            }
        } catch {
            // Silently ignore auto-attach errors so we don't break startup, but log them
            logger.error("Auto-attach current directory failed: \(error)")
        }
    }

    func promptForWriteAccess(reason: String, workspaceURI: String) -> Bool {
        print("\n\(TerminalUI.bold("⚠️  Write Access Requested"))")
        print("The assistant wants to modify files in this read-only workspace (\(workspaceURI)).")
        print("Reason: \(TerminalUI.dim(reason))")

        print("Grant full write access? [y/N] ", terminator: "")
        fflush(stdout)

        let answer = lineReader.readLine(prompt: "", completion: nil)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return answer == "y"
    }
}
