import Foundation
import MonadShared
import PKShared
import MonadShared
import Testing

@Suite("MonadShared Models")
struct MonadSharedModelsTests {
    @Test("MonadShared exports Monad API DTOs")
    func apiModelsAreCodable() throws {
        let request = ChatRequest(message: "Ping", requestOriginId: UUID())
        let timeline = TimelineResponse(id: UUID(), title: "Test")
        let page = PaginatedResponse(items: [timeline], metadata: PaginationMetadata(page: 1, perPage: 20, totalItems: 1))

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(request)
        #expect(try decoder.decode(ChatRequest.self, from: data).message == "Ping")
        #expect(try decoder.decode(PaginatedResponse<TimelineResponse>.self, from: encoder.encode(page)).items.count == 1)
    }

    @Test("MonadShared exports Monad-only tool definitions")
    func toolDefinitionsRemainAvailable() {
        #expect(InspectFileTool().callName == "inspect_file")
        #expect(RequestWriteAccessTool().callName == "request_write_access")
    }

    @Test("MonadShared exports PKLogHandler")
    func logHandlerCanBeConstructed() {
        let handler = PKLogHandler(label: "tests.monad.shared")
        #expect(handler.logLevel == .info)
    }
}
