import MonadCore

import Foundation
import GRDB

extension ClientIdentity: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "clientIdentity" }
}
