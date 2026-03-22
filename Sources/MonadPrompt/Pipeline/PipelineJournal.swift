import Foundation

// MARK: - Stable Hashing

/// Deterministic FNV-1a hash (stable across process invocations, unlike String.hashValue).
public enum StableHash {
    public static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325 // FNV offset basis
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0100_0000_01B3 // FNV prime
        }
        return hash
    }
}

// MARK: - Protocols

public protocol PipelineSnapshotEntry: Sendable {
    var entryId: String { get }
    var contentHash: UInt64 { get }
}

public protocol PipelineSnapshot: Sendable {
    associatedtype Entry: PipelineSnapshotEntry
    var entries: [Entry] { get }
}

// MARK: - JournalDiff

public struct JournalDiff<Entry: PipelineSnapshotEntry>: Sendable {
    /// Entries unchanged from the start (same position, same ID, same hash).
    public let stablePrefixCount: Int
    /// Entries with same ID but different hash.
    public let changed: [Entry]
    /// Entries not in previous snapshot.
    public let added: [Entry]
    /// Entry IDs removed since previous snapshot.
    public let removed: [String]

    public var hasChanges: Bool {
        !changed.isEmpty || !added.isEmpty || !removed.isEmpty
    }

    public static func initial(entries: [Entry]) -> JournalDiff<Entry> {
        JournalDiff(stablePrefixCount: 0, changed: [], added: entries, removed: [])
    }
}

// MARK: - PipelineJournal

public struct PipelineJournal<S: PipelineSnapshot>: Sendable {
    public private(set) var base: S?

    public init() {}

    @discardableResult
    public mutating func record(_ snapshot: S) -> JournalDiff<S.Entry> {
        defer { base = snapshot }
        guard let previous = base else {
            return .initial(entries: snapshot.entries)
        }

        // Stable prefix: positional match (same ID + same hash at same index)
        var stablePrefixCount = 0
        for idx in 0 ..< min(previous.entries.count, snapshot.entries.count) {
            if previous.entries[idx].entryId == snapshot.entries[idx].entryId
                && previous.entries[idx].contentHash == snapshot.entries[idx].contentHash
            {
                stablePrefixCount += 1
            } else { break }
        }

        // Changed / added / removed (by ID, not position)
        var previousById: [String: UInt64] = [:]
        for entry in previous.entries {
            previousById[entry.entryId] = entry.contentHash
        }

        var changed: [S.Entry] = []
        var added: [S.Entry] = []
        var seenIds: Set<String> = []
        for entry in snapshot.entries {
            seenIds.insert(entry.entryId)
            if let prevHash = previousById[entry.entryId] {
                if prevHash != entry.contentHash { changed.append(entry) }
            } else { added.append(entry) }
        }
        let removed = previous.entries.map(\.entryId).filter { !seenIds.contains($0) }

        return JournalDiff(
            stablePrefixCount: stablePrefixCount,
            changed: changed, added: added, removed: removed
        )
    }

    /// Resets the journal. The current base is preserved — only append counters
    /// (managed by the caller) are expected to reset. The next record() will diff
    /// against the existing base, correctly showing only what actually changed.
    /// Call with `hard: true` to fully clear (next record treats everything as new).
    public mutating func compact(hard: Bool = false) {
        if hard { base = nil }
    }
}
