import Foundation
import GRDB

extension PersistenceService {
    public func saveNote(_ note: Note) throws {
        logger.debug("Saving note: \(note.name)")
        try dbQueue.write {
            try note.save($0)
        }
    }

    public func fetchNote(id: UUID) throws -> Note? {
        try dbQueue.read {
            try Note.fetchOne($0, key: ["id": id])
        }
    }

    public func fetchAllNotes() throws -> [Note] {
        try dbQueue.read {
            try Note
                .order(Column("name").asc)
                .fetchAll($0)
        }
    }

    public func searchNotes(query: String) throws -> [Note] {
        guard !query.isEmpty else {
            return try fetchAllNotes()
        }

        return try dbQueue.read {
            let pattern = "%\(query)%"
            return try Note
                .filter(
                    Column("name").like(pattern) || Column("description").like(pattern)
                        || Column("content").like(pattern)
                )
                .order(Column("name").asc)
                .fetchAll($0)
        }
    }
    
    public func searchNotes(matchingAnyTag tags: [String]) throws -> [Note] {
        guard !tags.isEmpty else { return [] }
        
        return try dbQueue.read {
            var conditions: [SQLExpression] = []
            for tag in tags {
                conditions.append(Column("tags").like("%\(tag)%"))
            }
            
            let query = conditions.joined(operator: .or)
            let candidates = try Note.filter(query).fetchAll($0)
            
            return candidates.filter {
                let noteTags = Set($0.tagArray.map { $0.lowercased() })
                return !noteTags.intersection(tags.map { $0.lowercased() }).isEmpty
            }
        }
    }

    public func deleteNote(id: UUID) throws {
        try dbQueue.write {
            if let note = try Note.fetchOne($0, key: ["id": id]), note.isReadonly {
                throw NoteError.noteIsReadonly
            }
            try Note.deleteOne($0, key: ["id": id])
        }
    }

    public func getContextNotes() throws -> String {
        let notes = try fetchAllNotes()
        guard !notes.isEmpty else { return "" }

        return notes.map {
            """
            ### \($0.name)
            \($0.content)
            """
        }.joined(separator: "\n\n")
    }
}
