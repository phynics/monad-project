import Foundation
import GRDB

extension WorkspaceURI: DatabaseValueConvertible {
    public var databaseValue: DatabaseValue {
        description.databaseValue
    }

    public static func fromDatabaseValue(_ dbValue: DatabaseValue) -> WorkspaceURI? {
        guard let string = String.fromDatabaseValue(dbValue) else { return nil }
        return WorkspaceURI(parsing: string)
    }
}
