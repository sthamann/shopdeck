import XCTest
import PDFKit
@testable import ShopdeckCore

final class PickingWorkTests: XCTestCase {
    private let one = String(repeating: "a", count: 32), two = String(repeating: "b", count: 32)
    private func order(_ shop: Shop, _ id: String, state: String = "open") throws -> PickingOrder { try .init(shop: shop, data: .object(["id": .string(id), "orderNumber": .string("ORDER-" + String(id.prefix(4))), "stateMachineState": .object(["technicalName": .string(state)])])) }
    private func line(_ id: Int, order: String, quantity: Int, product: String = "product", sku: String = "SKU-1", good: Bool = true, type: String = "product") -> JSONValue {
        .object(["id": .string(String(format: "%032x", id)), "orderId": .string(order), "quantity": .number(Double(quantity)), "productId": .string(product), "label": .string("Café lamp"), "good": .bool(good), "type": .string(type), "payload": .object(["productNumber": .string(sku)])])
    }
    func testPickingSeparatesShopsVariantsAndHistoricalSKUsAndExcludesNonPhysicalLines() throws {
        let a = DemoData.shops[0], b = DemoData.shops[1]
        let orders = try [order(a, one), order(a, two), order(b, one), order(b, two, state: "cancelled")]
        let rows: [(Shop, JSONValue)] = [(a,line(1,order:one,quantity:2)),(a,line(2,order:two,quantity:3)),(b,line(3,order:one,quantity:7)),(a,line(4,order:one,quantity:4,product:"variant-2")),(a,line(5,order:one,quantity:1,sku:"NEW-SKU")),(a,line(6,order:one,quantity:10,good:false)),(a,line(7,order:one,quantity:1,type:"promotion")),(b,line(8,order:two,quantity:99))]
        let batch = try PickingList.assemble(orders: orders, lines: rows)
        XCTAssertEqual(batch.items.count, 4); XCTAssertEqual(batch.units, 17)
        XCTAssertEqual(batch.excludedOrders, 1); XCTAssertEqual(batch.excludedLines, 2)
        let combined = try XCTUnwrap(batch.items.first { $0.shop.id == a.id && $0.quantity == 5 })
        XCTAssertEqual(combined.allocations.map(\.quantity), [2,3]); XCTAssertEqual(combined.allocations.count, 2)
        XCTAssertFalse(batch.items.contains { $0.quantity == 99 })
        XCTAssertThrowsError(try PickingList.assemble(orders: [orders[0],orders[0]], lines: []))
    }
    func testPickingCSVAndMultipagePDFKeepEveryOrderAndCheckMark() throws {
        let shop = DemoData.shops[0]
        let orders = try (1...200).map { try order(shop, String(format: "%032x", $0)) }
        let batch = try PickingList.assemble(orders: orders, lines: orders.enumerated().map { (shop,line($0.offset+1,order:$0.element.orderID,quantity:1)) })
        XCTAssertEqual(batch.items.count, 1); XCTAssertEqual(batch.units, 200)
        let headings = ["Shop","SKU","Product","Quantity","Orders","Checked"], checked: Set<String> = [batch.items[0].id]
        let csv = String(decoding: PickingList.csv(items: batch.items, checked: checked, headings: headings), as: UTF8.self)
        XCTAssertTrue(csv.contains("Café lamp")); XCTAssertTrue(csv.contains("\"200.0\"")); XCTAssertTrue(csv.contains("\"true\""))
        let bytes = try PickingList.pdf(items: batch.items, checked: checked, title: "Picking list", subtitle: "Fixture", headings: headings)
        let pdf = try XCTUnwrap(PDFDocument(data: bytes)); XCTAssertGreaterThan(pdf.pageCount, 1)
        XCTAssertTrue(pdf.string?.contains("Quantity: 200") == true)
        XCTAssertEqual(pdf.string?.components(separatedBy: "× 1").count, 201)
    }
    func testRelativeDateRangesUseCalendarDaysAndExclusiveEndsAcrossDST() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let now = ISO8601DateFormatter().date(from: "2026-10-25T12:00:00Z")!
        let today = RecordDateRange.today.interval(now: now, calendar: calendar)
        XCTAssertEqual(today.duration, 25 * 3600)
        let filter = RecordDateRange.today.filter(field: "orderDateTime"), fmt = ISO8601DateFormatter()
        let criteria = try filter.criteria(now: now, calendar: calendar)
        XCTAssertEqual(criteria["parameters"]["gte"].string, fmt.string(from: today.start))
        XCTAssertEqual(criteria["parameters"]["lt"].string, fmt.string(from: today.end))
        XCTAssertTrue(filter.matches(.object(["orderDateTime": .string(fmt.string(from: today.start))]), now: now, calendar: calendar))
        XCTAssertFalse(filter.matches(.object(["orderDateTime": .string(fmt.string(from: today.end))]), now: now, calendar: calendar))
        let tomorrow = now.addingTimeInterval(26 * 3600)
        XCTAssertNotEqual(try filter.criteria(now: tomorrow, calendar: calendar), criteria)
        let month = RecordDateRange.lastMonth.interval(now: now, calendar: calendar)
        XCTAssertEqual(calendar.component(.month, from: month.start), 9); XCTAssertEqual(calendar.component(.month, from: month.end), 10)
        XCTAssertThrowsError(try RecordDateRange.today.filter(field:"stock").criteria())
    }
    func testBookmarksAndDynamicSavedViewSurviveRestartWithoutChangingShopData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try WorkspaceStore(directory: directory); try store.addDemoShops()
        let before = try Data(contentsOf: directory.appendingPathComponent("workspace.json"))
        let item = try RecordBookmark(shopID: DemoData.shops[0].id, entity: "product", recordID: one, title: "Lamp")
        try store.toggleBookmark(item)
        var view = SavedView(name: "Today", destination: "orders", shopID: nil); view.filters = [RecordDateRange.today.filter(field:"orderDateTime")]
        try store.updateWorkbench { $0.savedViews = [view] }
        let restored = try WorkspaceStore(directory: directory).readWorkbench()
        XCTAssertEqual(restored.bookmarks, [item]); XCTAssertEqual(restored.savedViews[0].filters?[0].value, "today")
        try store.toggleBookmark(item); XCTAssertTrue(try store.readWorkbench().bookmarks!.isEmpty)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("workspace.json")), before)
        XCTAssertNil(try JSONDecoder().decode(Workbench.self, from: Data("{\"savedViews\":[]}".utf8)).bookmarks)
    }
    func testServerPaginationLoadsAllLinesAndRefusesIncompleteLists() async throws {
        let shop = Shop(name: "Remote", url: "https://picking.example")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: directory) }
        let credentials = MemoryCredentials(); try credentials.save(.init(clientID: "fixture", clientSecret: "fixture"), for: shop.id)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let client = ShopwareClient(store: try WorkspaceStore(directory: directory), credentials: credentials, session: URLSession(configuration: config))
        let id = one, shopOrder = try order(shop, id), lines = (1...301).map { line($0, order: id, quantity: 1) }
        var pages: [Int] = []
        MockProtocol.handler = { request in
            if request.url!.path.hasSuffix("oauth/token") { return (200, .object(["access_token": .string("fixture"), "expires_in": .number(600)])) }
            let body = try Self.body(request)
            if request.url!.path.hasSuffix("search/order") { return (200, .object(["data": .array([.object(["id": .string(id), "orderNumber": .string(shopOrder.number), "stateMachineState": .object(["technicalName": .string("open")])])])])) }
            XCTAssertTrue(request.url!.path.hasSuffix("search/order-line-item"))
            XCTAssertEqual(body["filter"].array.first?["field"].string, "orderId")
            XCTAssertEqual(body["includes"]["order_line_item"].array.contains(.string("good")), true)
            let page = Int(body["page"].number!); pages.append(page)
            return (200, .object(["data": .array(Array(lines.dropFirst((page - 1) * 100).prefix(100))), "total": .number(301)]))
        }
        defer { MockProtocol.handler = nil }
        let selected: [FederatedRecord] = [.init(shop: shop, data: .object(["id": .string(id)]))]
        let batch = try await client.pickingList(selected)
        XCTAssertEqual(batch.units, 301); XCTAssertEqual(pages, [1,2,3,4])
        MockProtocol.handler = { request in
            if request.url!.path.hasSuffix("search/order") { return (200, .object(["data": .array([.object(["id": .string(id), "orderNumber": .string("fixture"), "stateMachineState": .object(["technicalName": .string("open")])])])])) }
            let page = Int(try Self.body(request)["page"].number ?? 1)
            return (200, .object(["data": .array(page == 1 ? Array(lines.prefix(100)) : []), "total": .number(301)]))
        }
        do { _ = try await client.pickingList(selected); XCTFail("An incomplete picking list must not be returned.") } catch { XCTAssertTrue(error.localizedDescription.contains("vollständig")) }
    }
    func testRelativeRangeIsSentToServerAndFrozenAcrossPagination() async throws {
        let shop = Shop(name: "Dates", url: "https://dates.example")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: directory) }
        let credentials = MemoryCredentials(); try credentials.save(.init(clientID: "fixture", clientSecret: "fixture"), for: shop.id)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let client = ShopwareClient(store: try WorkspaceStore(directory: directory), credentials: credentials, session: URLSession(configuration: config))
        let filter = RecordDateRange.today.filter(field: "orderDateTime")
        let frozen = try filter.freezingDateRange(now: Date()); XCTAssertEqual(frozen.map(\.operation), ["gte", "lt"])
        MockProtocol.handler = { request in
            if request.url!.path.hasSuffix("oauth/token") { return (200, .object(["access_token": .string("fixture"), "expires_in": .number(600)])) }
            let body = try Self.body(request), filters = body["filter"].array
            XCTAssertTrue(filters.contains { $0["field"].string == "orderDateTime" && $0["parameters"]["gte"].string != nil })
            XCTAssertTrue(filters.contains { $0["field"].string == "orderDateTime" && $0["parameters"]["lt"].string != nil })
            return (200, .object(["data": .array([]), "total": .number(0)]))
        }
        defer { MockProtocol.handler = nil }
        _ = try await client.searchAcrossShops([shop], entity: "order", filters: [shop.id: [filter]])
        XCTAssertEqual(filter.operation, "dateRange")
    }
    private static func body(_ request: URLRequest) throws -> JSONValue {
        if let data = request.httpBody { return try JSONDecoder().decode(JSONValue.self, from: data) }
        guard let stream = request.httpBodyStream else { return .null }; stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(contentsOf: buffer.prefix(n)) }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }
    func testAPIFieldErrorNamesTheFieldWithoutEchoingSubmittedValues() async throws {
        let shop = Shop(name: "Errors", url: "https://errors.example")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: directory) }
        let credentials = MemoryCredentials(); try credentials.save(.init(clientID: "fixture", clientSecret: "fixture"), for: shop.id)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockProtocol.self]
        let client = ShopwareClient(store: try WorkspaceStore(directory: directory), credentials: credentials, session: URLSession(configuration: config))
        MockProtocol.handler = { request in
            if request.url!.path.hasSuffix("oauth/token") { return (200, .object(["access_token": .string("fixture"), "expires_in": .number(600)])) }
            return (400, .object(["errors": .array([.object(["code": .string("FRAMEWORK__WRITE_UNEXPECTED_FIELD_ERROR"), "detail": .string("private submitted value"), "meta": .object(["parameters": .object(["field": .string("apiAlias")])])])])]))
        }
        defer { MockProtocol.handler = nil }
        do { _ = try await client.adminRequest(shop, request: .init(method: "POST", path: "product", body: .object([:]))); XCTFail() }
        catch { XCTAssertTrue(error.localizedDescription.contains("apiAlias")); XCTAssertFalse(error.localizedDescription.contains("private submitted value")) }
    }
    func testLivePickingTemporaryPhysicalFixtureAndRelativeServerFilter() async throws {
        guard ProcessInfo.processInfo.environment["SHOPDECK_PICKING_LIVE"] == "1" else { throw XCTSkip("Disposable position fixture on the isolated local verification shop.") }
        let shop = try XCTUnwrap(try WorkspaceStore().read().shops.first { $0.url == "http://127.0.0.1:18888" })
        let helper = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Shopdeck.app/Contents/Helpers/shopdeck-keychain")
        let process = Process(), pipe = Pipe(); process.executableURL = helper; process.arguments = ["load", shop.id.uuidString]; process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        struct Reply: Decodable { let status: Int32; let credentials: Credentials? }
        let reply = try JSONDecoder().decode(Reply.self, from: data); XCTAssertEqual(reply.status, 0)
        let credentials = MemoryCredentials(); try credentials.save(XCTUnwrap(reply.credentials), for: shop.id)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: directory) }
        let client = ShopwareClient(store: try WorkspaceStore(directory: directory), credentials: credentials)
        let result = try await client.search(shop, entity: "order", limit: 100, customFilters: [RecordDateRange.today.filter(field:"orderDateTime")])
        XCTAssertGreaterThan(result.rows.count, 0)
        let target = try XCTUnwrap(result.rows.first { $0["orderNumber"].string == "SHOPDECK-TEST-1001" })
        let orderID = try XCTUnwrap(target["id"].string)
        let inspection = try await client.adminRequest(shop, request: .init(method: "POST", path: "search/order-line-item", body: .object(["limit": .number(100), "filter": .array([.object(["type": .string("equals"), "field": .string("orderId"), "value": .string(orderID)])])])) )
        let original = inspection["data"].array
        let selected: [FederatedRecord] = [.init(shop: shop, data: target)]
        let baseline = try await client.pickingList(selected)
        let expected = original.filter { $0["type"].string == "product" && $0["good"].bool == true }.reduce(0) { $0 + Int($1["quantity"].number ?? 0) }
        XCTAssertEqual(baseline.units, expected)
        let products = try await client.search(shop, entity: "product", limit: 1)
        let product = try XCTUnwrap(products.rows.first), productID = try XCTUnwrap(product["id"].string), sku = try XCTUnwrap(product["productNumber"].string)
        let fixtureID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        var fixture: [String: JSONValue] = ["id": .string(fixtureID), "orderId": .string(orderID), "identifier": .string(fixtureID), "referencedId": .string(productID), "productId": .string(productID), "type": .string("product"), "good": .bool(true), "label": .string("SHOPDECK PICKING VERIFICATION"), "quantity": .number(1), "position": .number(9999), "payload": .object(["productNumber": .string(sku)])]
        func cleanReadMetadata(_ value: JSONValue) -> JSONValue {
            if let object = value.object { return .object(object.filter { !["apiAlias", "extensions"].contains($0.key) }.mapValues(cleanReadMetadata)) }
            if case .array(let rows) = value { return .array(rows.map(cleanReadMetadata)) }; return value
        }
        fixture["price"] = cleanReadMetadata(try XCTUnwrap(original.first?["price"]))
        _ = try await client.adminRequest(shop, request: .init(method: "POST", path: "order-line-item", body: .object(fixture)))
        do {
            let batch = try await client.pickingList(selected)
            XCTAssertEqual(batch.units, expected + 1)
            XCTAssertTrue(batch.items.contains { $0.title == "SHOPDECK PICKING VERIFICATION" && $0.sku == sku })
            XCTAssertEqual(batch.orders.count, 1)
        } catch {
            _ = try? await client.adminRequest(shop, request: .init(method: "DELETE", path: "order-line-item/" + fixtureID)); throw error
        }
        _ = try await client.adminRequest(shop, request: .init(method: "DELETE", path: "order-line-item/" + fixtureID))
        let restored = try await client.pickingList(selected); XCTAssertEqual(restored.units, baseline.units)
        let after = try await client.detail(shop, entity: "order", id: orderID, resolveInheritance: false)
        XCTAssertEqual(after["amountTotal"], target["amountTotal"])
        XCTAssertEqual(Set(after["lineItems"].array.compactMap { $0["id"].string }), Set(original.compactMap { $0["id"].string }))
        print("Live picking: physical fixture included, original custom position excluded, calendar filter applied on server, fixture removed, original order amount and positions preserved.")
    }
}
