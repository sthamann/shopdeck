import XCTest
@testable import ShopdeckCore

final class MemoryCredentials: CredentialStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: Credentials] = [:]
    func load(for id: UUID) throws -> Credentials { lock.lock(); defer { lock.unlock() }; guard let c = values[id] else { throw ShopdeckError.message("missing") }; return c }
    func save(_ c: Credentials, for id: UUID) throws { lock.lock(); defer { lock.unlock() }; values[id] = c }
    func delete(for id: UUID) throws { lock.lock(); defer { lock.unlock() }; values[id] = nil }
}
final class MockProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (Int, JSONValue))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do { let (status, json) = try Self.handler!(request); let data = try JSONEncoder().encode(json); client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed); client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self) }
        catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class ShopdeckCoreTests: XCTestCase {
    func temporaryStore() throws -> WorkspaceStore { try WorkspaceStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("shopdeck-test-\(UUID())")) }
    func request(_ method: String, _ params: JSONValue = .object([:]), id: Double = 1) -> JSONValue { .object(["jsonrpc": .string("2.0"), "id": .number(id), "method": .string(method), "params": params]) }
    func testURLAndIDValidation() throws {
        XCTAssertEqual(try Validation.shopURL("https://example.com/subshop/").path.trimmingCharacters(in: CharacterSet(charactersIn: "/")), "subshop")
        XCTAssertNoThrow(try Validation.shopURL("http://127.0.0.1:8888"))
        for url in ["http://example.com", "file:///tmp/x", "https://user:password@example.com", "https://example.com?secret=1"] { XCTAssertThrowsError(try Validation.shopURL(url)) }
        XCTAssertThrowsError(try Validation.entityID("../../oauth/token"))
    }
    func testProductChangesRejectUnexpectedAndInvalidFields() {
        for changes: [String: JSONValue] in [["price": .number(1)], ["stock": .number(-1)], ["stock": .number(1.5)], ["active": .string("yes")], ["name": .string(" ")], [:]] { XCTAssertThrowsError(try Validation.productChanges(changes)) }
        XCTAssertNoThrow(try Validation.productChanges(["stock": .number(0), "active": .bool(false)]))
    }
    func testAtomicWorkspaceUpdatesFromSeparateStoreInstances() throws {
        let store = try temporaryStore(), second = try WorkspaceStore(directory: store.directory)
        DispatchQueue.concurrentPerform(iterations: 80) { i in try! (i % 2 == 0 ? store : second).update { $0.activities.append(Activity(title: "\(i)", detail: "")) } }
        XCTAssertEqual(try store.read().activities.count, 80)
        XCTAssertEqual(try store.read().activities.map(\.title).sorted(), (0..<80).map(String.init).sorted())
    }
    func testMCPProposalDoesNotWriteUntilApprovedAndRedactsPII() async throws {
        let store = try temporaryStore(); try store.addDemoShops()
        let api = ShopwareClient(store: store), server = MCPServer(store: store, client: api), shop = DemoData.shops[0]
        _ = await server.handle(request("initialize", .object(["protocolVersion": .string("2025-11-25")])))
        let products = try await api.search(shop, entity: "product", limit: 1)
        let product = products.rows[0], id = product["id"].string!
        let args: JSONValue = .object(["shop_id": .string(shop.id.uuidString), "product_id": .string(id), "changes": .object(["stock": .number(42)]), "reason": .string("Restock")])
        let response = await server.handle(request("tools/call", .object(["name": .string("propose_product_change"), "arguments": args])))
        XCTAssertEqual(response?["result"]["isError"].bool, false)
        XCTAssertEqual(try store.read().proposals.count, 1)
        let unchanged = try await api.detail(shop, entity: "product", id: id)
        XCTAssertEqual(unchanged["stock"], product["stock"])
        let orders = await server.handle(request("tools/call", .object(["name": .string("search_orders"), "arguments": .object(["shop_id": .string(shop.id.uuidString)])])))
        XCTAssertFalse(orders!.pretty.contains("customer1@example.com"))
        XCTAssertFalse(orders!.pretty.contains("orderCustomer"))
        try await api.updateProduct(shop, id: id, changes: ["stock": .number(42)])
        let changed = try await api.detail(shop, entity: "product", id: id)
        XCTAssertEqual(changed["stock"].number, 42)
    }
    func testMCPAccessCanBeRevokedWhileProcessRuns() async throws {
        let store = try temporaryStore(); try store.addDemoShops()
        let server = MCPServer(store: store, client: ShopwareClient(store: store))
        _ = await server.handle(request("initialize"))
        try store.update { $0.shops[0].mcpEnabled = false }
        let response = await server.handle(request("tools/call", .object(["name": .string("shop_overview"), "arguments": .object(["shop_id": .string(DemoData.shops[0].id.uuidString)])])))
        XCTAssertEqual(response?["result"]["isError"].bool, true)
    }
    func testModernAndLegacyMCPDiscovery() async throws {
        let store = try temporaryStore(), server = MCPServer(store: store, client: ShopwareClient(store: store))
        let modern: JSONValue = .object(["_meta": .object(["io.modelcontextprotocol/protocolVersion": .string("2026-07-28")])])
        let discover = await server.handle(request("server/discover", modern))
        XCTAssertEqual(discover?["result"]["supportedVersions"].array, [.string("2026-07-28")])
        let list = await server.handle(request("tools/list", modern))
        XCTAssertEqual(list?["result"]["tools"].array.count, 20)
        XCTAssertEqual(list?["result"]["resultType"].string, "complete")
        let legacy = await server.handle(request("initialize", .object(["protocolVersion": .string("2025-06-18")])))
        XCTAssertEqual(legacy?["result"]["protocolVersion"].string, "2025-06-18")
        XCTAssertEqual(legacy?["result"]["resultType"], .null)
    }
    func testRulesAllAnyScopeAndCurrency() throws {
        let shop = UUID(), other = UUID(), order: JSONValue = .object(["amountTotal": .number(150), "currency": .object(["isoCode": .string("EUR")]), "orderCustomer": .object(["email": .string("alice@example.com")])])
        let conditions = [OrderCondition(value: "100"), OrderCondition(field: "currency.isoCode", comparison: "eq", value: "EUR")]
        XCTAssertTrue(OrderRule(name: "VIP", shopID: shop, conditions: conditions).matches(order, shopID: shop))
        XCTAssertFalse(OrderRule(name: "VIP", shopID: other, conditions: conditions).matches(order, shopID: shop))
        XCTAssertFalse(OrderRule(name: "VIP", conditions: conditions + [OrderCondition(value: "200")]).matches(order, shopID: shop))
        XCTAssertTrue(OrderRule(name: "VIP", conditions: conditions + [OrderCondition(value: "200")], matchAll: false).matches(order, shopID: shop))
        XCTAssertTrue(OrderCondition(field: "orderCustomer.email", comparison: "contains", value: "@EXAMPLE.COM").matches(order))
        XCTAssertTrue(OrderCondition(field: "amountTotal", comparison: "eq", value: "150,00").matches(order))
        XCTAssertFalse(OrderCondition(field: "missing", comparison: "gte", value: "1").matches(order))
    }
    func testVersionComparisonHandlesFourComponentsAndExcludesPrerelease() {
        XCTAssertTrue(VersionComparison.isNewer("v6.7.10.1", than: "6.7.9.0"))
        XCTAssertFalse(VersionComparison.isNewer("6.7.10.0", than: "6.7.10.1"))
        XCTAssertFalse(VersionComparison.isNewer("6.8.0.0-rc1", than: "6.7.10.1"))
    }
    func testInstallerPreservesOtherServersAndBacksUpFiles() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("shopdeck-install-\(UUID())")
        let existing = "model = \"test\"\n[mcp_servers.other]\ncommand = \"other\"\n[mcp_servers.shopdeck]\ncommand = \"old\"\n[mcp_servers.last]\ncommand = \"last\"\n"
        let config = home.appendingPathComponent(".codex/config.toml"); try FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true); try existing.write(to: config, atomically: true, encoding: .utf8)
        let installer = ClientInstaller(home: home), helper = URL(fileURLWithPath: "/usr/bin/true"), destination = home.appendingPathComponent("bin/shopdeck-mcp")
        _ = try installer.install(.codex, helper: helper, destination: destination)
        _ = try installer.install(.codex, helper: helper, destination: destination)
        let merged = try String(contentsOf: config)
        XCTAssertTrue(merged.contains("model = \"test\"")); XCTAssertTrue(merged.contains("[mcp_servers.other]")); XCTAssertTrue(merged.contains("[mcp_servers.last]")); XCTAssertEqual(merged.components(separatedBy: "[mcp_servers.shopdeck]").count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent(".agents/skills/shopdeck/SKILL.md").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: config.deletingLastPathComponent().path).filter { $0.contains("backup") }.count, 2)
        let json = try ClientInstaller.mergedJSON(Data("{\"theme\":\"dark\",\"mcpServers\":{\"other\":{\"command\":\"x\"}}}".utf8), command: "/safe path/helper", rootKey: "mcpServers")
        let result = try JSONDecoder().decode(JSONValue.self, from: json)
        XCTAssertEqual(result["mcpServers"]["other"]["command"].string, "x"); XCTAssertEqual(result["theme"].string, "dark")
        XCTAssertThrowsError(try ClientInstaller.mergedJSON(Data("[]".utf8), command: "x", rootKey: "mcpServers"))
    }
    func testOAuthSearchPaginationAnd401Refresh() async throws {
        let store = try temporaryStore(), credentials = MemoryCredentials(), shop = Shop(name: "Test", url: "https://example.com/subshop")
        try credentials.save(Credentials(clientID: "id", clientSecret: "secret"), for: shop.id)
        var tokens = 0, searches = 0
        MockProtocol.handler = { request in
            if request.url!.path.hasSuffix("oauth/token") { tokens += 1; return (200, .object(["access_token": .string("token-\(tokens)"), "expires_in": .number(3600)])) }
            searches += 1
            XCTAssertEqual(request.url?.path, "/subshop/api/search/product")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            if searches == 1 { return (401, .object([:])) }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token-2")
            return (200, .object(["total": .number(120), "data": .array([.object(["id": .string(String(repeating: "a", count: 32)), "name": .string("Real API product")])])]))
        }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let client = ShopwareClient(store: store, credentials: credentials, session: URLSession(configuration: config))
        let data = try await client.search(shop, entity: "product", page: 2, limit: 50)
        XCTAssertEqual(data.total, 120); XCTAssertEqual(tokens, 2); XCTAssertEqual(searches, 2)
    }
    func testLiveDockerBootstrapAndReadWrite() async throws {
        guard let url = ProcessInfo.processInfo.environment["SHOPDECK_LIVE_URL"] else { throw XCTSkip("Set SHOPDECK_LIVE_URL to an isolated local Dockware test container") }
        let store = try temporaryStore(), credentials = MemoryCredentials(), client = ShopwareClient(store: store, credentials: credentials)
        var shop = Shop(name: "Live verification", url: url, environment: "Lokal", mcpEnabled: true); shop.containerName = "shopdeck-verification-1106"
        let generated = try await client.bootstrapLocal(shop)
        print("Live: integration created and authenticated")
        try credentials.save(generated, for: shop.id)
        let version = try await client.version(shop)
        print("Live: version \(version)")
        XCTAssertTrue(version.hasPrefix("6."))
        let channels = try await client.salesChannels(shop)
        XCTAssertFalse(channels.isEmpty)
        let totals = try await client.revenueMonths(shop)
        XCTAssertTrue(totals.allSatisfy{$0.month.range(of:"^[0-9]{4}-[0-9]{2}$",options:.regularExpression) != nil})
        XCTAssertGreaterThan(totals.filter{$0.currency=="EUR"}.reduce(0){$0+$1.revenue},0)
        let security = try await client.securityPlugin(shop)
        XCTAssertEqual(security.state,.missing)
        try await client.configureLocalDomains(shop,credentials:generated)
        let configured = try await client.salesChannels(shop)
        XCTAssertTrue(configured.flatMap(\.domains).filter{$0.safeURL?.host=="127.0.0.1"}.allSatisfy{$0.safeURL?.port==18888})
        print("Live: channels, calendar revenue, security status and storefront domain verified")
        let stockDescending = try await client.search(shop,entity:"product",limit:2,sort:[.init("stock",ascending:false),.init("id")])
        let allProducts = try await client.search(shop,entity:"product",limit:100,sort:[.init("stock",ascending:false),.init("id")])
        XCTAssertEqual(stockDescending.rows,Array(allProducts.rows.prefix(2)))
        let secondProductPage=try await client.search(shop,entity:"product",page:2,limit:2,sort:[.init("stock",ascending:false),.init("id")])
        XCTAssertEqual(secondProductPage.rows,Array(allProducts.rows.dropFirst(2).prefix(2)))
        let actualFiltered=try await client.searchAcrossShops([shop],entity:"product",term:stockDescending.rows.first?["name"].string ?? "",pageSize:1,maximum:50,sort:[.init("stock",ascending:false)])
        XCTAssertEqual(actualFiltered.rows.first?.data["id"],stockDescending.rows.first?["id"])
        print("Live: API column sorting, page two, search and bounded list path verified")
        let snapshot = try await client.snapshot(shop)
        print("Live: snapshot has \(snapshot.products) products")
        let productsWithInheritance = try await client.search(shop,entity:"product",limit:100)
        XCTAssertTrue(productsWithInheritance.rows.allSatisfy { !($0.at("name").string ?? "").isEmpty })
        XCTAssertTrue(productsWithInheritance.rows.allSatisfy { $0["active"].bool != nil })
        XCTAssertGreaterThan(snapshot.products, 0)
        let result = try await client.search(shop, entity: "product", limit: 1)
        let row = try XCTUnwrap(result.rows.first), id = try XCTUnwrap(row["id"].string), old = row["stock"]
        print("Live: product read; stock \(old)")
        let service = ProductChangeService(store: store, gateway: client)
        let next = (old.number ?? 0) + 1
        do {
            let applied = try await service.apply(shop, id: id, changes: ["stock": .number(next)], origin: "integration-test", expectedBefore: ["stock": old])
            let entry = try XCTUnwrap(applied)
            XCTAssertEqual(entry.status, .applied)
            let updated = try await client.detail(shop, entity: "product", id: id)
            XCTAssertEqual(updated["stock"].number, next)
            let reversal = try await service.undo(entry.id, shop: shop)
            XCTAssertEqual(reversal?.status, .applied)
            let restored = try await client.detail(shop, entity: "product", id: id)
            XCTAssertEqual(restored["stock"], old)
            print("Live: journaled write and undo verified")
            for entity in ["product", "order", "customer"] {
                let records = try await client.search(shop, entity: entity, limit: 1)
                if let record = records.rows.first, let entityID = record["id"].string {
                    let detail = try await client.detail(shop, entity: entity, id: entityID)
                    XCTAssertEqual(detail["id"].string, entityID)
                    print("Live: \(entity) detail loaded with \(detail.object?.count ?? 0) fields")
                }
            }
            if ProcessInfo.processInfo.environment["SHOPDECK_REGISTER_LOCAL"] == "1" {
                let appStore = try WorkspaceStore()
                let existing = try appStore.read().shops.first { $0.url == url && !$0.isDemo }
                var connected = existing ?? shop; connected.name = "Shopware Lokal"; connected.mcpEnabled = false
                try KeychainStore().save(generated, for: connected.id)
                try appStore.update { state in state.shops.removeAll { $0.id == connected.id }; state.shops.append(connected) }
                print("Live: local testshop connected in Shopdeck")
            }
        } catch {
            try await client.updateProduct(shop, id: id, changes: ["stock": old])
            throw error
        }
    }
}
