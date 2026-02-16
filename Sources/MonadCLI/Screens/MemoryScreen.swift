import MonadShared
import Foundation
import MonadClient

class MemoryScreen {
    private let client: MonadClient
    private var memories: [Memory] = []
    private var searchQuery: String = ""
    private var currentPage: Int = 0
    private let pageSize: Int = 10
    private var totalCount: Int = 0

    // Cache for list vs search results to avoid refetching list when clearing search
    private var allMemories: [Memory] = []

    init(client: MonadClient) {
        self.client = client
    }

    func show(initialQuery: String? = nil) async throws {
        if let query = initialQuery, !query.isEmpty {
            try await performSearch(query)
        } else {
            // Initial fetch
            TerminalUI.printLoading("Fetching memories...")
            self.allMemories = try await client.listMemories()
            self.memories = self.allMemories
            self.totalCount = self.memories.count
        }

        while true {
            TerminalUI.clearScreen()
            render()

            print(TerminalUI.dim("──────────────────────────────────────────────────"))
            print("Commands: [q]uit, [n]ext, [p]rev, [s]earch <query>, <number> to view")
            print("> ", terminator: "")
            guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                break
            }

            if input.lowercased() == "q" {
                break
            } else if input.lowercased() == "n" {
                nextPage()
            } else if input.lowercased() == "p" {
                prevPage()
            } else if input.lowercased().starts(with: "s") {
                // Handle search
                let components = input.split(
                    separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                if components.count > 1 {
                    let query = String(components[1])
                    try await performSearch(query)
                } else {
                    // Reset search if just "s" or "search"
                    resetSearch()
                }
            } else if let index = Int(input) {
                if index > 0 && index <= currentVisibleItems.count {
                    viewDetail(memory: currentVisibleItems[index - 1])
                }
            }
        }
    }

    private var currentVisibleItems: [Memory] {
        let start = currentPage * pageSize
        let end = min(start + pageSize, memories.count)
        guard start < end else { return [] }
        return Array(memories[start..<end])
    }

    private func render() {
        print(TerminalUI.bold("🧠 Memory Explorer"))
        if !searchQuery.isEmpty {
            print("Search: \(TerminalUI.cyan(searchQuery))")
        }
        print(TerminalUI.dim("Total: \(memories.count) items"))
        print("")

        let items = currentVisibleItems
        if items.isEmpty {
            print(TerminalUI.dim("No memories found."))
            return
        }

        for (i, memory) in items.enumerated() {
            let globalIndex = (currentPage * pageSize) + i + 1
            let dateStr = TerminalUI.formatDate(memory.createdAt)

            // Format content preview (multiline)
            let contentLines = memory.content.split(separator: "\n").map { String($0) }
            let maxLines = 3

            print(
                "\(globalIndex). \(TerminalUI.dim(memory.id.uuidString.prefix(8).description)) | \(dateStr)"
            )

            for (lineIndex, line) in contentLines.prefix(maxLines).enumerated() {
                let prefix = lineIndex == 0 ? "   " : "   "
                let truncatedLine = line.count > 80 ? String(line.prefix(77)) + "..." : line
                print("\(prefix)\(truncatedLine)")
            }
            if contentLines.count > maxLines {
                print("   " + TerminalUI.dim("..."))
            }
        }

        print("")
        print(
            TerminalUI.dim(
                "Page \(currentPage + 1) of \(max(1, (memories.count + pageSize - 1) / pageSize))"))
    }

    private func nextPage() {
        if (currentPage + 1) * pageSize < memories.count {
            currentPage += 1
        }
    }

    private func prevPage() {
        if currentPage > 0 {
            currentPage -= 1
        }
    }

    private func performSearch(_ query: String) async throws {
        TerminalUI.printLoading("Searching...")
        self.searchQuery = query
        // Use semantic search from client
        self.memories = try await client.searchMemories(query, limit: 20)
        self.currentPage = 0
    }

    private func resetSearch() {
        self.searchQuery = ""
        self.memories = self.allMemories
        self.currentPage = 0
    }

    private func viewDetail(memory: Memory) {
        TerminalUI.clearScreen()
        print(TerminalUI.bold("Memory Details"))
        print(TerminalUI.dim("──────────────────────────────────────────────────"))
        print("ID:      \(memory.id.uuidString)")
        print("Created: \(TerminalUI.formatDate(memory.createdAt))")
        if !memory.tagArray.isEmpty {
            print("Tags:    \(memory.tagArray.joined(separator: ", "))")
        }
        print(TerminalUI.dim("──────────────────────────────────────────────────"))
        print(memory.content)
        print(TerminalUI.dim("──────────────────────────────────────────────────"))
        print("Press [Enter] to return list...")
        _ = readLine()
    }
}
