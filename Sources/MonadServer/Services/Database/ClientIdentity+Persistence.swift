import Foundation
import GRDB
import MonadShared

extension ClientIdentity: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "clientIdentity" }
}
