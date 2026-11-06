import XCTest
@testable import ShopdeckCore

final class ListConfigurationTests: XCTestCase {
    func testLegacySavedViewsAndColumnOrderSurviveReload() throws {
        let legacy = try JSONDecoder().decode(Workbench.self, from: Data("{\"savedViews\":[]}".utf8))
        XCTAssertNil(legacy.lists)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = try WorkspaceStore(directory: directory)
        var config = ListConfiguration.standard("product")
        config.columns.swapAt(0, 2); config.columns.append(.init("customFields.note", "Notiz", width: 233))
        config.filters = [.init(name: "Nachbestellen", field: "stock", operation: "lte", value: "10")]
        try store.updateWorkbench { $0.lists = ["product": config] }
        let restored = try WorkspaceStore(directory: directory).readWorkbench()
        XCTAssertEqual(restored.lists?["product"], config)
    }
    func testCustomFiltersApplyBeforePagingAndPreserveTotal() async throws {
        let store = try WorkspaceStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        try store.addDemoShops()
        let client = ShopwareClient(store: store)
        let filters = [RecordFilter(name: "Großer Bestand", field: "stock", operation: "gte", value: "30"), RecordFilter(name: "Aktiv", field: "active", value: "true")]
        let all = try await client.search(DemoData.shops[0], entity: "product", limit: 100, customFilters: filters)
        let page = try await client.search(DemoData.shops[0], entity: "product", page: 2, limit: 3, customFilters: filters)
        XCTAssertGreaterThan(all.total, 3)
        XCTAssertEqual(page.total, all.total)
        XCTAssertEqual(page.rows, Array(all.rows.dropFirst(3).prefix(3)))
        XCTAssertTrue(all.rows.allSatisfy { $0["stock"].number! >= 30 && $0["active"].bool == true })
        XCTAssertThrowsError(try RecordFilter(name: "Invalid", field: "stock);bad", value: "1").criteria())
        XCTAssertEqual(JSONValue.object(["price": .array([.object(["gross": .number(12)])])]).at("price.0.gross"), .number(12))
    }
    func testCustomCriteriaReachesShopwareAPI() async throws {
        let store = try WorkspaceStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), credentials = MemoryCredentials()
        let shop = Shop(name: "Mock", url: "https://test.example")
        try credentials.save(.init(clientID: "id", clientSecret: "secret"), for: shop.id)
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockProtocol.self]
        var captured: JSONValue = .null
        MockProtocol.handler = { request in
            if request.url!.path.hasSuffix("oauth/token") { return (200, .object(["access_token": .string("test"), "expires_in": .number(600)])) }
            if let data = request.httpBody { captured = try JSONDecoder().decode(JSONValue.self, from: data) }
            else if let stream = request.httpBodyStream { stream.open(); defer { stream.close() }; var data = Data(); var bytes = [UInt8](repeating: 0,count: 1024); while stream.hasBytesAvailable { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count)) }; captured = try JSONDecoder().decode(JSONValue.self, from: data) }
            return (200, .object(["data": .array([]), "total": .number(0)]))
        }
        defer { MockProtocol.handler = nil }
        let client = ShopwareClient(store: store, credentials: credentials, session: URLSession(configuration: configuration))
        _ = try await client.search(shop, entity: "order", page: 2, limit: 25, customFilters: [.init(name: "High value", field: "amountTotal", operation: "gte", value: "100")])
        XCTAssertEqual(captured["filter"].array.first?["field"].string, "amountTotal")
        XCTAssertEqual(captured["filter"].array.first?["parameters"]["gte"].number, 100)
        XCTAssertEqual(captured["page"].number, 2)
        XCTAssertEqual(captured["total-count-mode"].number, 1)
    }
}
