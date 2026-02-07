import Testing
import Hummingbird
import HummingbirdTesting
import Foundation
@testable import MonadServer

@Suite struct ErrorHandlingTests {

    @Test("Test Standardized Error Responses (Empty Body)")
    func testStandardizedErrorResponses() async throws {
        let router = Router()
        router.add(middleware: ErrorMiddleware())

        router.get("/error/404") { _, _ -> String in
            throw HTTPError(.notFound)
        }

        router.get("/error/500") { _, _ -> String in
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Internal failure"])
        }

        let app = Application(router: router)

        try await app.test(.router) { client in
            // 404 Case
            try await client.execute(uri: "/error/404", method: .get) { response in
                #expect(response.status == .notFound)
                #expect(response.body.readableBytes == 0, "Error response should have empty body per specification")
            }

            // 500 Case
            try await client.execute(uri: "/error/500", method: .get) { response in
                #expect(response.status == .internalServerError)
                #expect(response.body.readableBytes == 0, "Error response should have empty body per specification")
            }
        }
    }
}
