import XCTest
@testable import ShopdeckCore

final class MerchantWorkTests: XCTestCase {
    func testFocusFiltersMatchTheirMeaningAndExcludeInheritedContent() throws {
        let now = Date(timeIntervalSince1970: 1793966400)
        let old: JSONValue = .object(["stateMachineState": .object(["technicalName": .string("open")]), "orderDateTime": .string(ISO8601DateFormatter().string(from: now.addingTimeInterval(-49 * 3600)))])
        let recent: JSONValue = .object(["stateMachineState": .object(["technicalName": .string("open")]), "orderDateTime": .string(ISO8601DateFormatter().string(from: now.addingTimeInterval(-47 * 3600)))])
        let filters = MerchantFocus.overdueOrders.filters(overdueHours: 48, now: now)
        XCTAssertTrue(filters.allSatisfy { $0.matches(old) }); XCTAssertFalse(filters.allSatisfy { $0.matches(recent) })
        let root: JSONValue = .object(["active": .bool(true), "stock": .number(3), "description": .string("")])
        XCTAssertTrue(MerchantFocus.lowStock.filters(stockThreshold: 4).allSatisfy { $0.matches(root) })
        XCTAssertFalse(MerchantFocus.lowStock.filters(stockThreshold: 2).allSatisfy { $0.matches(root) })
        XCTAssertFalse(MerchantFocus.soldOut.filters().allSatisfy { $0.matches(root) })
        XCTAssertTrue(MerchantFocus.missingImage.filters().allSatisfy { $0.matches(root) })
        XCTAssertTrue(MerchantFocus.missingDescription.filters().allSatisfy { $0.matches(root) })
        var variant = root.object!; variant["parentId"] = .string(String(repeating: "a", count: 32))
        XCTAssertFalse(MerchantFocus.missingImage.filters().allSatisfy { $0.matches(.object(variant)) })
        let null = try MerchantFocus.missingImage.filters().last!.criteria()
        XCTAssertEqual(null["type"].string, "equals"); XCTAssertEqual(null["value"], .null)
        let empty = try MerchantFocus.missingDescription.filters().last!.criteria()
        XCTAssertEqual(empty["type"].string, "multi"); XCTAssertEqual(empty["queries"].array.count, 2)
    }
    func testFollowUpsSurviveReopenDedupeAndNeverModifyWorkspace() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try WorkspaceStore(directory: directory); try store.addDemoShops()
        let before = try Data(contentsOf: directory.appendingPathComponent("workspace.json"))
        var item = try RecordFollowUp(shopID: DemoData.shops[0].id, entity: "order", recordID: String(repeating: "A", count: 32), title: "#1001", note: "Call customer", dueAt: .distantPast)
        try store.saveFollowUp(item)
        item.note = "Waiting for reply"; try store.saveFollowUp(item)
        let reopened = try WorkspaceStore(directory: directory)
        XCTAssertEqual(try reopened.readWorkbench().followUps?.count, 1)
        let persisted = try XCTUnwrap(reopened.readWorkbench().followUps?.first)
        XCTAssertEqual(persisted.note, "Waiting for reply"); XCTAssertTrue(persisted.isDue())
        item.completedAt = Date(); try store.saveFollowUp(item)
        XCTAssertFalse(try XCTUnwrap(reopened.readWorkbench().followUps?.first).isDue())
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("workspace.json")), before)
        XCTAssertThrowsError(try RecordFollowUp(shopID: UUID(), entity: "integration", recordID: "invalid", title: "bad"))
        let old = try JSONDecoder().decode(Workbench.self, from: Data("{\"savedViews\":[]}".utf8))
        XCTAssertNil(old.followUps)
    }
    func testCSVPreservesColumnsUnicodeRowsAndGuardsSpreadsheetFormulas() throws {
        let shop = Shop(name: "Atelier, Köln", url: "https://example.com")
        let rows: [FederatedRecord] = (0..<75).map { i in .init(shop: shop, data: .object(["id": .string(String(i)), "name": .string(i == 0 ? "  =HYPERLINK(\"bad\")" : "Café\n\"\(i)\""), "stock": .number(Double(i)), "active": .bool(true)])) }
        let columns: [RecordColumn] = [.init("stock", "Stock"), .init("shop", "Shop"), .init("name", "Name"), .init("active", "Active")]
        let data = RecordCSV.encode(rows: rows, columns: columns), text = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(Array(data.prefix(3)), [0xef, 0xbb, 0xbf])
        XCTAssertTrue(text.contains("\"Stock\",\"Shop\",\"Name\",\"Active\""))
        XCTAssertTrue(text.contains("\"'  =HYPERLINK(\"\"bad\"\")\""))
        XCTAssertTrue(text.contains("\"74.0\",\"Atelier, Köln\",\"Café\n\"\"74\"\"\",\"true\""))
    }
    func testSavedViewRetainsMultipleShopSubset() throws {
        var view = SavedView(name: "Two warehouses", destination: "products", shopID: nil)
        view.shopIDs = [UUID(), UUID()]
        let restored = try JSONDecoder().decode(SavedView.self, from: JSONEncoder().encode(view))
        XCTAssertEqual(restored.shopIDs, view.shopIDs)
    }
    func testLiveFocusCountsAndMatchingRows() async throws {
        guard ProcessInfo.processInfo.environment["SHOPDECK_MERCHANT_LIVE"] == "1" else { throw XCTSkip("Opt in for read only checks on the isolated local verification shop.") }
        let original = try WorkspaceStore().read()
        let shop = try XCTUnwrap(original.shops.first { $0.url == "http://127.0.0.1:18888" })
        let helper = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Shopdeck.app/Contents/Helpers/shopdeck-keychain")
        let process = Process(), pipe = Pipe()
        process.executableURL = helper; process.arguments = ["load", shop.id.uuidString]; process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        struct Reply: Decodable { let status: Int32; let credentials: Credentials? }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        XCTAssertEqual(reply.status, 0)
        let credentials = MemoryCredentials(); try credentials.save(XCTUnwrap(reply.credentials), for: shop.id)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = ShopwareClient(store: try WorkspaceStore(directory: directory), credentials: credentials)
        let now = Date()
        for focus in MerchantFocus.allCases {
            let filters = focus.filters(now: now)
            let count = try await client.search(shop, entity: focus.entity, limit: 1, customFilters: filters, compact: true)
            let full = try await client.search(shop, entity: focus.entity, limit: 100, customFilters: filters)
            XCTAssertEqual(count.total, full.total)
            XCTAssertTrue(full.rows.allSatisfy { row in filters.allSatisfy { $0.matches(row) } }, focus.rawValue)
        }
        let products = try await client.searchAcrossShops([shop], entity: "product", pageSize: 100, maximum: 100, sort: [.init("stock", ascending: false)])
        XCTAssertTrue(products.failures.isEmpty); XCTAssertGreaterThan(products.rows.count, 0)
        let csv = RecordCSV.encode(rows: products.rows, columns: [.init("productNumber", "SKU"), .init("stock", "Stock"), .init("name", "Name")])
        XCTAssertGreaterThan(csv.count, 100)
        print("Live merchant work: six server counts and matching filters verified; filtered CSV generated.")
    }

}
