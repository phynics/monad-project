import Testing
import Hummingbird
import HummingbirdTesting
import Foundation
@testable import MonadServer
import NIOCore

@Suite struct AuthMiddlewareTests {

    @Test("Test Missing Auth Header")
    func testMissingAuthHeader() async throws {
        let router = Router(context: BasicRequestContext.self)
        router.add(middleware: AuthMiddleware(token: "secret-token"))
        router.get("/") { _, _ in
            return "OK"
        }

        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(uri: "/", method: .get) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("Test Invalid Auth Header")
    func testInvalidAuthHeader() async throws {
        let router = Router(context: BasicRequestContext.self)
        router.add(middleware: AuthMiddleware(token: "secret-token"))
        router.get("/") { _, _ in
            return "OK"
        }

        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/",
                method: .get,
                headers: [.authorization: "Bearer wrong-token"]
            ) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }
    
    @Test("Test Missing Bearer Prefix")
    func testMissingBearerPrefix() async throws {
        let router = Router(context: BasicRequestContext.self)
        router.add(middleware: AuthMiddleware(token: "secret-token"))
        router.get("/") { _, _ in
            return "OK"
        }

        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/",
                method: .get,
                headers: [.authorization: "secret-token"]
            ) { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("Test Valid Auth Header")
    func testValidAuthHeader() async throws {
        let router = Router(context: BasicRequestContext.self)
        router.add(middleware: AuthMiddleware(token: "secret-token"))
        router.get("/") { _, _ in
            return "OK"
        }

        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/",
                method: .get,
                headers: [.authorization: "Bearer secret-token"]
            ) { response in
                #expect(response.status == .ok)
            }
        }
    }
}
