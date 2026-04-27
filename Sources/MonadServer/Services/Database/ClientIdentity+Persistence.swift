import PKShared
import PositronicKit

import Foundation
import GRDB

extension ClientIdentity: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String { "clientIdentity" }
}
