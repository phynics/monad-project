import Foundation
import Hummingbird
import MonadShared

public extension Request {
    /// Parse pagination parameters from query string
    func getPagination(defaultPerPage: Int = 20) -> PaginationRequest {
        let components = URLComponents(string: uri.description)
        let queryItems = components?.queryItems
        let page = queryItems?.first(where: { $0.name == "page" })?
            .value.flatMap(Int.init) ?? 1
        let perPage = queryItems?.first(where: { $0.name == "perPage" })?
            .value.flatMap(Int.init) ?? defaultPerPage
        return PaginationRequest(page: page, perPage: perPage)
    }
}
