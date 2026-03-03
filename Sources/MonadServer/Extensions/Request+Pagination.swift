import MonadShared

import Hummingbird
import Foundation

extension Request {
    /// Parse pagination parameters from query string
    public func getPagination(defaultPerPage: Int = 20) -> PaginationRequest {
        let components = URLComponents(string: self.uri.description)
        let page = components?.queryItems?.first(where: { $0.name == "page" })?.value.flatMap(Int.init) ?? 1
        let perPage = components?.queryItems?.first(where: { $0.name == "perPage" })?.value.flatMap(Int.init) ?? defaultPerPage
        return PaginationRequest(page: page, perPage: perPage)
    }
}
