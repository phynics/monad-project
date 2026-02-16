import MonadShared
import Foundation
import MonadClient
import MonadCore

struct JobSlashCommand: SlashCommand {
    let name = "job"
    let aliases = ["jobs"]
    let description = "Manage background jobs"
    let category: String? = "Tools & Environment"
    let usage = "/job <action> [arguments]"

    func run(args: [String], context: ChatContext) async throws {
        guard !args.isEmpty else {
            printUsage()
            return
        }

        let action = args[0]
        let subArgs = Array(args.dropFirst())

        switch action {
        case "add":
            try await addJob(args: subArgs, context: context)
        case "list":
            try await listJobs(context: context)
        case "show":
            try await showJob(args: subArgs, context: context)
        case "delete":
            try await deleteJob(args: subArgs, context: context)
        default:
            TerminalUI.printError("Unknown action: \(action)")
            printUsage()
        }
    }

    private func printUsage() {
        print(TerminalUI.bold("Usage: /job <action> [arguments]"))
        print("Actions:")
        print("  add <title> [description]  Add a new background job")
        print("  list                       List all jobs in the current session")
        print("  show <jobId>               Show details of a specific job")
        print("  delete <jobId>             Delete a job")
    }

    private func addJob(args: [String], context: ChatContext) async throws {
        guard !args.isEmpty else {
            TerminalUI.printError("Usage: /job add <title> [description]")
            return
        }

        let jobTitle = args.joined(separator: " ")
        
        let job = try await context.client.addJob(sessionId: context.session.id, title: jobTitle, priority: 0)
        TerminalUI.printSuccess("Job added: \(job.title) (ID: \(job.id))")
    }

    private func listJobs(context: ChatContext) async throws {
        let jobs = try await context.client.listJobs(sessionId: context.session.id)
        if jobs.isEmpty {
            print("No jobs found for this session.")
            return
        }

        print(TerminalUI.bold("Jobs for Session \(context.session.title ?? "Untitled"):"))
        for job in jobs {
            let statusColor: (String) -> String
            switch job.status {
            case .pending: statusColor = TerminalUI.yellow
            case .inProgress: statusColor = TerminalUI.blue
            case .completed: statusColor = TerminalUI.green
            case .failed, .cancelled: statusColor = TerminalUI.red
            }
            
            print("- [\(statusColor(job.status.rawValue))] \(job.title) (ID: \(job.id))")
        }
    }

    private func showJob(args: [String], context: ChatContext) async throws {
        guard let idString = args.first, let id = UUID(uuidString: idString) else {
            TerminalUI.printError("Invalid Job ID")
            return
        }
        
        // Fetch specific or search in list?
        // Client has `getJob`.
        do {
            let job = try await context.client.getJob(sessionId: context.session.id, jobId: id)
            print(TerminalUI.bold("Job Details:"))
            print("ID: \(job.id)")
            print("Title: \(job.title)")
            print("Status: \(job.status.rawValue)")
            print("Priority: \(job.priority)")
            if let desc = job.description {
                print("Description: \(desc)")
            }
            print("Created: \(job.createdAt)")
            print("Updated: \(job.updatedAt)")
        } catch {
             TerminalUI.printError("Job not found or error: \(error)")
        }
    }

    private func deleteJob(args: [String], context: ChatContext) async throws {
         guard let idString = args.first, let id = UUID(uuidString: idString) else {
            TerminalUI.printError("Invalid Job ID")
            return
        }
        
        try await context.client.deleteJob(sessionId: context.session.id, jobId: id)
        TerminalUI.printSuccess("Job deleted.")
    }
}
