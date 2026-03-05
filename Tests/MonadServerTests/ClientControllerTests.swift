import Foundation
import GRDB
import Hummingbird
import HummingbirdTesting
import MonadCore
@testable import MonadServer
import MonadShared
import Testing

@Suite(.serialized)
@MainActor
struct ClientControllerTests {
    private let persistence: PersistenceService

    init() async throws {
        let queue = try DatabaseQueue()
        var migrator = DatabaseMigrator()
        DatabaseSchema.registerMigrations(in: &migrator)
        try migrator.migrate(queue)
        persistence = PersistenceService(dbQueue: queue)
    }

    private func makeApp() -> some ApplicationProtocol {
        let router = Router()
        let controller = ClientAPIController<BasicRequestContext>(persistenceService: persistence)
        controller.addRoutes(to: router.group("/clients"))
        return Application(router: router)
    }

    // MARK: - POST /clients/register

    @Test("POST /clients/register creates a client and returns 201")
    func register_returnsCreatedClient() async throws {
        let app = makeApp()
        let requestBody = ClientRegistrationRequest(
            hostname: "test-host.local",
            displayName: "Test User",
            platform: "macos",
            tools: []
        )
        let body = try JSONEncoder().encode(requestBody)

        try await app.test(.router) { client in
            try await client.execute(
                uri: "/clients/register",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(bytes: body)
            ) { response in
                #expect(response.status == .created)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let registration = try decoder.decode(ClientRegistrationResponse.self, from: response.body)
                #expect(registration.client.hostname == "test-host.local")
                #expect(registration.client.displayName == "Test User")
                #expect(registration.defaultWorkspace.hostType == .client)
            }
        }
    }

    @Test("POST /clients/register persists the client and its workspace")
    func register_persistsClientAndWorkspace() async throws {
        let app = makeApp()
        let body = try JSONEncoder().encode(ClientRegistrationRequest(
            hostname: "laptop.local",
            displayName: "dev",
            platform: "macos",
            tools: []
        ))

        nonisolated(unsafe) var registeredClientId: UUID?
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/clients/register",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(bytes: body)
            ) { response in
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let registration = try decoder.decode(ClientRegistrationResponse.self, from: response.body)
                let id = registration.client.id
                registeredClientId = id
            }
        }

        let fetchedClient = try await persistence.fetchClient(id: #require(registeredClientId))
        #expect(fetchedClient != nil)
        #expect(fetchedClient?.hostname == "laptop.local")
    }

    // MARK: - GET /clients/:id

    @Test("GET /clients/:id returns registered client")
    func getClient_returnsClient() async throws {
        let app = makeApp()
        let body = try JSONEncoder().encode(ClientRegistrationRequest(
            hostname: "mac.local", displayName: "me", platform: "macos", tools: []
        ))

        nonisolated(unsafe) var clientId: UUID?
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/clients/register",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(bytes: body)
            ) { response in
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let reg = try decoder.decode(ClientRegistrationResponse.self, from: response.body)
                clientId = reg.client.id
            }
        }

        try await app.test(.router) { client in
            try await client.execute(uri: "/clients/\(clientId!.uuidString)", method: .get) { response in
                #expect(response.status == .ok)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let identity = try decoder.decode(ClientIdentity.self, from: response.body)
                #expect(identity.id == clientId)
                #expect(identity.hostname == "mac.local")
            }
        }
    }

    @Test("GET /clients/:id returns 404 when client not found")
    func getClient_notFound_returns404() async throws {
        let app = makeApp()
        try await app.test(.router) { client in
            try await client.execute(uri: "/clients/\(UUID().uuidString)", method: .get) { response in
                #expect(response.status == .notFound)
            }
        }
    }

    // MARK: - GET /clients

    @Test("GET /clients returns all registered clients")
    func listClients_returnsAll() async throws {
        let app = makeApp()

        for index in 1 ... 3 {
            let body = try JSONEncoder().encode(ClientRegistrationRequest(
                hostname: "host\(index).local", displayName: "user\(index)", platform: "macos", tools: []
            ))
            try await app.test(.router) { client in
                try await client.execute(
                    uri: "/clients/register",
                    method: .post,
                    headers: [.contentType: "application/json"],
                    body: ByteBuffer(bytes: body)
                ) { _ in }
            }
        }

        try await app.test(.router) { client in
            try await client.execute(uri: "/clients", method: .get) { response in
                #expect(response.status == .ok)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let clients = try decoder.decode([ClientIdentity].self, from: response.body)
                #expect(clients.count == 3)
            }
        }
    }

    // MARK: - DELETE /clients/:id

    @Test("DELETE /clients/:id returns 204 and removes client")
    func deleteClient_returnsNoContent() async throws {
        let app = makeApp()
        let body = try JSONEncoder().encode(ClientRegistrationRequest(
            hostname: "temp.local", displayName: "temp", platform: "macos", tools: []
        ))

        nonisolated(unsafe) var clientId: UUID?
        try await app.test(.router) { client in
            try await client.execute(
                uri: "/clients/register",
                method: .post,
                headers: [.contentType: "application/json"],
                body: ByteBuffer(bytes: body)
            ) { response in
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let reg = try decoder.decode(ClientRegistrationResponse.self, from: response.body)
                clientId = reg.client.id
            }
        }

        try await app.test(.router) { client in
            try await client.execute(uri: "/clients/\(clientId!.uuidString)", method: .delete) { response in
                #expect(response.status == .noContent)
            }
        }

        let remaining = try await persistence.fetchClient(id: #require(clientId))
        #expect(remaining == nil)
    }

    @Test("DELETE /clients/:id returns 404 when client not found")
    func deleteClient_notFound_returns404() async throws {
        let app = makeApp()
        try await app.test(.router) { client in
            try await client.execute(uri: "/clients/\(UUID().uuidString)", method: .delete) { response in
                #expect(response.status == .notFound)
            }
        }
    }
}
