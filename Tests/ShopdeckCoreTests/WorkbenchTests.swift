import XCTest
@testable import ShopdeckCore

final class WorkbenchTests: XCTestCase {
    func testSavedViewsSurviveWorkspaceWritesAndReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("shopdeck-views-\(UUID())")
        let store = try WorkspaceStore(directory: directory)
        let shop = DemoData.shops[0]
        let view = SavedView(name: "Stock", destination: "products", shopID: shop.id, query: "Backpack", lowStock: true, status: "active")
        try store.updateWorkbench { $0.savedViews.append(view) }
        try store.update { $0.activities.append(Activity(title: "MCP write", detail: "")) }
        let reopened = try WorkspaceStore(directory: directory)
        XCTAssertEqual(try reopened.readWorkbench().savedViews, [view])
        XCTAssertEqual(try reopened.read().activities.count, 1)
    }
    func testStatusAndStockFiltersComposeBeforePagination() async throws {
        let store = try WorkspaceStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("shopdeck-filters-\(UUID())"))
        let client = ShopwareClient(store: store), shop = DemoData.shops[0]
        let result = try await client.search(shop, entity: "product", limit: 1, lowStock: true, status: "active")
        XCTAssertEqual(result.total, 3)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows[0]["active"].bool, true)
        XCTAssertLessThanOrEqual(result.rows[0]["stock"].number ?? 99, 5)
        let orders = try await client.search(shop, entity: "order", status: "completed")
        XCTAssertEqual(orders.total, 6)
        XCTAssertTrue(orders.rows.allSatisfy { $0["stateMachineState"]["technicalName"].string == "completed" })
        XCTAssertThrowsError(try SearchFilters.criteria(entity: "product", lowStock: false, status: "cancelled"))
        let filters = try SearchFilters.criteria(entity: "product", lowStock: true, status: "inactive")
        XCTAssertEqual(filters.count, 2)
        XCTAssertEqual(filters[1]["value"].bool, false)
    }
}
