import PKShared
import MonadShared
import PositronicKit

import Foundation
import GRDB

extension RequestOriginIdentity: @retroactive FetchableRecord, @retroactive PersistableRecord {
    public static var databaseTableName: String { "requestOrigin" }
}
