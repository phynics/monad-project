import Foundation
import Hummingbird
import HummingbirdTesting
import MonadCore
@testable import MonadServer
import MonadShared
import Testing

@Suite struct ErrorHandlingTests {
    // MARK: - HTTPError

    @Test("HTTPError.notFound maps to http_error code with 404 status")
    func httpError_notFound_mapsToHttpError() async throws {
        let router = Router()
        router.add(middleware: ErrorMiddleware())
        router.get("/err") { _, _ -> String in throw HTTPError(.notFound) }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(uri: "/err", method: .get) { response in
                #expect(response.status == .notFound)
                let apiError = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                #expect(apiError.error.code == "http_error")
            }
        }
    }

    @Test("Unhandled error maps to 500 internal_server_error")
    func unhandledError_maps500() async throws {
        let router = Router()
        router.add(middleware: ErrorMiddleware())
        router.get("/err") { _, _ -> String in
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Internal failure"])
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(uri: "/err", method: .get) { response in
                #expect(response.status == .internalServerError)
                let apiError = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                #expect(apiError.error.code == "internal_server_error")
            }
        }
    }

    // MARK: - ToolError

    @Test("ToolError.toolNotFound maps to 404 tool_not_found")
    func toolError_toolNotFound_maps404() async throws {
        let router = Router()
        router.add(middleware: ErrorMiddleware())
        router.get("/err") { _, _ -> String in throw MonadCore.ToolError.toolNotFound("my_tool") }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(uri: "/err", method: .get) { response in
                #expect(response.status == .notFound)
                let apiError = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                #expect(apiError.error.code == "tool_not_found")
            }
        }
    }

    @Test("ToolError.workspaceNotFound maps to 404 workspace_not_found")
    func toolError_workspaceNotFound_maps404() async throws {
        let router = Router()
        router.add(middleware: ErrorMiddleware())
        router.get("/err") { _, _ -> String in throw MonadCore.ToolError.workspaceNotFound(UUID()) }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(uri: "/err", method: .get) { response in
                #expect(response.status == .notFound)
                let apiError = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                #expect(apiError.error.code == "workspace_not_found")
            }
        }
    }

    @Test("ToolError.missingArgument maps to 400 missing_argument")
    func toolError_missingArgument_maps400() async throws {
        let router = Router()
        router.add(middleware: ErrorMiddleware())
        router.get("/err") { _, _ -> String in throw MonadCore.ToolError.missingArgument("path") }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(uri: "/err", method: .get) { response in
                #expect(response.status == .badRequest)
                let apiError = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                #expect(apiError.error.code == "missing_argument")
            }
        }
    }

    @Test("ToolError.invalidArgument maps to 400 invalid_argument")
    func toolError_invalidArgument_maps400() async throws {
        let router = Router()
        router.add(middleware: ErrorMiddleware())
        router.get("/err") { _, _ -> String in
            throw MonadCore.ToolError.invalidArgument("param", expected: "String", got: "Int")
        }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(uri: "/err", method: .get) { response in
                #expect(response.status == .badRequest)
                let apiError = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                #expect(apiError.error.code == "invalid_argument")
            }
        }
    }

    @Test("ToolError.clientNotConnected maps to 503 client_not_connected")
    func toolError_clientNotConnected_maps503() async throws {
        let router = Router()
        router.add(middleware: ErrorMiddleware())
        router.get("/err") { _, _ -> String in throw MonadCore.ToolError.clientNotConnected }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(uri: "/err", method: .get) { response in
                #expect(response.status == .serviceUnavailable)
                let apiError = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                #expect(apiError.error.code == "client_not_connected")
            }
        }
    }

    @Test("ToolError.executionFailed maps to 500 execution_failed")
    func toolError_executionFailed_maps500() async throws {
        let router = Router()
        router.add(middleware: ErrorMiddleware())
        router.get("/err") { _, _ -> String in throw MonadCore.ToolError.executionFailed("timeout") }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(uri: "/err", method: .get) { response in
                #expect(response.status == .internalServerError)
                let apiError = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                #expect(apiError.error.code == "execution_failed")
            }
        }
    }

    @Test("ToolError.clientExecutionRequired maps to 500 client_execution_required")
    func toolError_clientExecutionRequired_maps500() async throws {
        let router = Router()
        router.add(middleware: ErrorMiddleware())
        router.get("/err") { _, _ -> String in throw MonadCore.ToolError.clientExecutionRequired }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(uri: "/err", method: .get) { response in
                #expect(response.status == .internalServerError)
                let apiError = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                #expect(apiError.error.code == "client_execution_required")
            }
        }
    }

    // MARK: - SessionError

    @Test("SessionError.sessionNotFound maps to 404 session_not_found")
    func sessionError_sessionNotFound_maps404() async throws {
        let router = Router()
        router.add(middleware: ErrorMiddleware())
        router.get("/err") { _, _ -> String in throw SessionError.sessionNotFound }
        let app = Application(router: router)

        try await app.test(.router) { client in
            try await client.execute(uri: "/err", method: .get) { response in
                #expect(response.status == .notFound)
                let apiError = try JSONDecoder().decode(APIErrorResponse.self, from: response.body)
                #expect(apiError.error.code == "session_not_found")
            }
        }
    }
}
