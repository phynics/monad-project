import Testing
import Foundation
@testable import MonadShared
import ErrorKit

@Suite("MonadError Protocol Tests")
struct MonadErrorTests {

    struct MockError: MonadError {
        let errorDomain: String
        let errorCode: Int
        let userFriendlyMessage: String
        let remediation: String? = nil
    }

    @Test("MonadError formatting includes domain and code")
    func testMonadErrorFormatting() {
        let error = MockError(
            errorDomain: MonadErrorDomain.shared,
            errorCode: 123,
            userFriendlyMessage: "Something failed"
        )

        #expect(error.errorDescription == "[com.monad.shared:123] Something failed")
    }

    @Test("MonadErrorDomain constants are correct")
    func testMonadErrorDomains() {
        #expect(MonadErrorDomain.shared == "com.monad.shared")
        #expect(MonadErrorDomain.client == "com.monad.client")
        #expect(MonadErrorDomain.server == "com.monad.server")
        #expect(MonadErrorDomain.llm == "com.monad.core.llm")
        #expect(MonadErrorDomain.context == "com.monad.core.context")
    }
}
