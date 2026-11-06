import XCTest
@testable import ShopdeckCore

private actor TestProductGateway: ProductGateway {
    enum Mode: Equatable { case normal, loseReply, loseVerification, reject }
    private var product: JSONValue = .object(["name": .string("Test product"), "stock": .number(5), "active": .bool(true)])
    private var mode = Mode.normal
    private var verificationUnavailable = false
    private(set) var writes = 0
    func configure(_ mode: Mode) { self.mode = mode; verificationUnavailable = false }
    func replace(_ fields: [String: JSONValue]) { var object = product.object!; object.merge(fields) { _, new in new }; product = .object(object) }
    func detail(_ shop: Shop, entity: String, id: String) async throws -> JSONValue {
        if verificationUnavailable { throw ShopdeckError.message("verification offline") }
        return product
    }
    func updateProduct(_ shop: Shop, id: String, changes: [String: JSONValue]) async throws {
        writes += 1
        if mode == .reject { throw ShopdeckError.message("rejected") }
        replace(changes)
        if mode == .loseReply { throw ShopdeckError.message("reply lost") }
        if mode == .loseVerification { verificationUnavailable = true }
    }
    func restoreProduct(_ shop: Shop, id: String, changes: [String: JSONValue]) async throws { try await updateProduct(shop, id: id, changes: changes) }
}

final class ProductChangeTests: XCTestCase {
    let productID = String(repeating: "a", count: 32)
    func store() throws -> WorkspaceStore { try WorkspaceStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("shopdeck-journal-\(UUID())")) }
    func testBeforeAfterUndoAndNewerFieldConflict() async throws {
        let store = try store(), gateway = TestProductGateway(), shop = DemoData.shops[0]
        let service = ProductChangeService(store: store, gateway: gateway)
        let entryResult = try await service.apply(shop, id: productID, changes: ["stock": .number(15)], origin: "bulk")
        let entry = try XCTUnwrap(entryResult)
        XCTAssertEqual(entry.before["stock"], .number(5)); XCTAssertEqual(entry.after["stock"], .number(15)); XCTAssertEqual(entry.status, .applied)
        await gateway.replace(["stock": .number(19)])
        do { _ = try await service.undo(entry.id, shop: shop); XCTFail("Must not overwrite a newer stock value") } catch {}
        let writeCount = await gateway.writes; XCTAssertEqual(writeCount, 1)
        await gateway.replace(["stock": .number(15), "name": .string("Newer name")])
        let undone = try await service.undo(entry.id, shop: shop)
        XCTAssertEqual(undone?.status, .applied)
        let current = try await gateway.detail(shop, entity: "product", id: productID)
        XCTAssertEqual(current["stock"], .number(5)); XCTAssertEqual(current["name"].string, "Newer name")
        let reopened = try WorkspaceStore(directory: store.directory).readProductJournal()
        XCTAssertEqual(reopened.changes.count, 2)
        XCTAssertEqual(reopened.changes.first?.status, .undone)
        do { _ = try await service.undo(entry.id, shop: shop); XCTFail("Must not undo twice") } catch {}
    }
    func testLostResponseIsVerifiedAndUnknownWriteBlocksRetry() async throws {
        let store = try store(), gateway = TestProductGateway(), shop = DemoData.shops[0]
        let service = ProductChangeService(store: store, gateway: gateway)
        await gateway.configure(.loseReply)
        let applied = try await service.apply(shop, id: productID, changes: ["stock": .number(7)], origin: "editor")
        XCTAssertEqual(applied?.status, .applied)
        await gateway.configure(.loseVerification)
        let pendingResult = try await service.apply(shop, id: productID, changes: ["stock": .number(9)], origin: "editor")
        let pending = try XCTUnwrap(pendingResult)
        XCTAssertEqual(pending.status, .uncertain)
        await gateway.configure(.normal)
        do { _ = try await service.apply(shop, id: productID, changes: ["stock": .number(11)], origin: "editor"); XCTFail("Resolve unknown outcome first") } catch {}
        let writeCount = await gateway.writes; XCTAssertEqual(writeCount, 2)
        let reconciled = try await service.reconcile(pending.id, shop: shop)
        XCTAssertEqual(reconciled.status, .applied)
        let restored = try await service.undo(pending.id, shop: shop)
        XCTAssertEqual(restored?.status, .applied)
    }
    func testPreviewRejectsNegativeStockAndDetectsChangeBeforeApply() async throws {
        let store = try store(), gateway = TestProductGateway(), shop = DemoData.shops[0]
        let service = ProductChangeService(store: store, gateway: gateway)
        do { _ = try await service.preview(shop, id: productID, draft: BulkProductDraft(stock: -10, stockMode: .adjust)); XCTFail("Stock cannot become negative") } catch {}
        let plan = try await service.preview(shop, id: productID, draft: BulkProductDraft(stock: 10, stockMode: .adjust))
        XCTAssertEqual(plan.before["stock"], .number(5)); XCTAssertEqual(plan.after["stock"], .number(15))
        await gateway.replace(["stock": .number(8)])
        do { _ = try await service.apply(shop, id: productID, changes: plan.after, origin: "bulk", expectedBefore: plan.before); XCTFail("Stale preview must be rejected") } catch {}
        let writeCount = await gateway.writes; XCTAssertEqual(writeCount, 0)
        XCTAssertTrue(try store.readProductJournal().changes.isEmpty)
    }
    func testJournalMustBeWritableBeforeShopWriteAndInheritanceCanBeRestored() async throws {
        let store = try store(), gateway = TestProductGateway(), shop = DemoData.shops[0]
        let service = ProductChangeService(store: store, gateway: gateway)
        let file = store.directory.appendingPathComponent("product-changes.json")
        try Data("broken".utf8).write(to: file)
        do { _ = try await service.apply(shop, id: productID, changes: ["stock": .number(8)], origin: "editor"); XCTFail("Do not write without a journal") } catch {}
        let writeCount = await gateway.writes; XCTAssertEqual(writeCount, 0)
        try FileManager.default.removeItem(at: file)
        await gateway.replace(["name": .null])
        let namedResult = try await service.apply(shop, id: productID, changes: ["name": .string("Explicit name")], origin: "editor")
        let named = try XCTUnwrap(namedResult)
        _ = try await service.undo(named.id, shop: shop)
        let restored = try await gateway.detail(shop, entity: "product", id: productID)
        XCTAssertEqual(restored["name"], .null)
    }
    func testLargeBatchPersistsAcrossReopenAndRetryCannotOverwriteNewerValues()async throws {
        let store=try store(),gateway=TestProductGateway(),shop=DemoData.shops[0]
        let service=ProductChangeService(store:store,gateway:gateway),batch="ai-batch:"+UUID().uuidString
        var last:ProductChangeRecord?
        for index in 1...120 {last=try await service.apply(shop,id:productID,changes:["stock":.number(Double(index+5))],origin:batch,operationID:UUID())}
        let reopened=try WorkspaceStore(directory:store.directory).readProductJournal();XCTAssertEqual(reopened.changes.count,120);XCTAssertTrue(reopened.changes.allSatisfy{$0.status == .applied && $0.origin==batch})
        let receipt=try XCTUnwrap(last);await gateway.replace(["stock":.number(777)])
        let retry=try await service.apply(shop,id:productID,changes:["stock":.number(125)],origin:batch,operationID:receipt.operationID)
        XCTAssertEqual(retry?.id,receipt.id);let current=try await gateway.detail(shop,entity:"product",id:productID);XCTAssertEqual(current["stock"],.number(777));let writes=await gateway.writes;XCTAssertEqual(writes,120)
        do{_ = try await service.undo(receipt.id,shop:shop);XCTFail("Must protect a newer external edit") }catch{}
        await gateway.replace(["stock":.number(125)])
        for record in reopened.changes.reversed(){let undone=try await service.undo(record.id,shop:shop);XCTAssertEqual(undone?.status,.applied)}
        let restored=try await gateway.detail(shop,entity:"product",id:productID);XCTAssertEqual(restored["stock"],.number(5));let journal=try store.readProductJournal();XCTAssertEqual(journal.changes.count,240);XCTAssertEqual(journal.changes.filter{$0.status == .undone}.count,120)
    }
    func testAdministrationURLsPreserveShopSubdirectory() throws {
        let shop = Shop(name: "Subshop", url: "https://example.com/commerce")
        XCTAssertEqual(try ShopLinks.administration(shop).absoluteString, "https://example.com/commerce/admin/")
        XCTAssertThrowsError(try ShopLinks.administration(Shop(name: "Invalid", url: "https://user:secret@example.com")))
    }
}
