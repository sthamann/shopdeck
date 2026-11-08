import XCTest
import PDFKit
@testable import ShopdeckCore

final class DesktopWorkflowTests: XCTestCase {
    func testSessionRoundTripPreservesIndependentScopesAndRepairsDeletedShops() throws {
        let a = UUID(), b = UUID(), channel = String(repeating: "a", count: 32)
        var first = DesktopTab(); first.destination = "orders"; first.shopIDs = [a, b]; first.query = "paid café"; first.page = 4
        first.filters = [.init(name: "Payment", field: "amountTotal", operation: "gt", value: "100")]
        first.sort = [.init("amountTotal", ascending: false)]; first.channelKey = a.uuidString + ":" + channel; first.currency = "USD"
        var second = DesktopTab(); second.destination = "admin"; second.shopID = b
        let original = DesktopSession(tabs: [first, second], selected: first.id, secondary: second.id)
        let restored = try JSONDecoder().decode(DesktopSession.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored, original)
        let pruned = restored.validated(shopIDs: [a])
        XCTAssertEqual(pruned.tabs[0].shopIDs, [a]); XCTAssertEqual(pruned.tabs[0].page, 4)
        XCTAssertEqual(pruned.tabs[0].channelKey, first.channelKey); XCTAssertEqual(pruned.tabs[0].currency, "USD")
        XCTAssertNil(pruned.tabs[1].shopID); XCTAssertEqual(pruned.tabs[1].destination, "overview")
        var corrupt = original; corrupt.tabs.append(first); corrupt.selected = UUID(); corrupt.secondary = corrupt.selected
        XCTAssertEqual(corrupt.validated(shopIDs: [a,b]).tabs.count, 2)
        XCTAssertEqual(corrupt.validated(shopIDs: [a,b]).selected, first.id)
        XCTAssertNil(corrupt.validated(shopIDs: [a,b]).secondary)
    }
    func testSavedWorkspacesDoNotModifyShopDataAndSurviveReopen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try WorkspaceStore(directory: directory); try store.addDemoShops()
        let before = try Data(contentsOf: directory.appendingPathComponent("workspace.json"))
        var tab = DesktopTab(); tab.destination = "products"; tab.query = "chair"
        let session = DesktopSession(tabs: [tab], selected: tab.id)
        try store.updateDesktopState { $0.lastSession = session; $0.presets = [.init(name: "  Morning review  ", session: session)] }
        let reopened = try WorkspaceStore(directory: directory).readDesktopState()
        XCTAssertEqual(reopened.lastSession, session); XCTAssertEqual(reopened.presets.first?.name, "Morning review")
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("workspace.json")), before)
    }
    func testChannelReferenceWorksBeforeCatalogHasLoadedAndRejectsMalformedKeys() throws {
        let shop = UUID(), channel = String(repeating: "a", count: 32)
        let resolved = try XCTUnwrap(CommerceChannelReference.resolve(shop.uuidString + ":" + channel))
        XCTAssertEqual(resolved.shopID, shop); XCTAssertEqual(resolved.id, channel)
        XCTAssertNil(try CommerceChannelReference.resolve(nil))
        for bad in ["bad", shop.uuidString + ":../../order", shop.uuidString + ":" + channel + ":extra"] { XCTAssertThrowsError(try CommerceChannelReference(key: bad)) }
    }
    func testReminderPlanExcludesPastCompletedDisabledAndDisconnectedAndKeepsNotesPrivate() throws {
        let shop = Shop(name: "Atelier", url: "https://example.com"), now = Date()
        var enabled = try RecordFollowUp(shopID: shop.id, entity: "order", recordID: String(repeating: "a", count: 32), title: "#1001", note: "PRIVATE customer conversation", dueAt: now.addingTimeInterval(120))
        enabled.reminderEnabled = true
        var completed = enabled; completed.id = UUID(); completed.completedAt = now
        var disabled = enabled; disabled.id = UUID(); disabled.reminderEnabled = false
        var past = enabled; past.id = UUID(); past.dueAt = now.addingTimeInterval(-1)
        var disconnected = enabled; disconnected.id = UUID(); disconnected.shopID = UUID()
        let plan = FollowUpReminder.plan(items: [completed, disabled, past, disconnected, enabled], shops: [shop], now: now)
        XCTAssertEqual(plan.count, 1); XCTAssertEqual(plan[0].id, FollowUpReminder.prefix + enabled.id.uuidString)
        XCTAssertEqual(plan[0].recordTitle, "#1001"); XCTAssertFalse(String(describing: plan).contains("PRIVATE"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try WorkspaceStore(directory: directory); try store.saveFollowUp(enabled)
        XCTAssertEqual(try store.readWorkbench().followUps?.first?.reminderEnabled, true)
    }
    func testDocumentRouteFilenameAndOriginalPDFPreview() throws {
        let shop = DemoData.shops[0], id = String(repeating: "a", count: 32)
        let data: JSONValue = .object(["id": .string(id), "orderId": .string(id), "deepLinkCode": .string(String(repeating: "b", count: 32)), "documentType": .object(["technicalName": .string("invoice")]), "config": .object(["documentNumber": .string("../../" + String(repeating: "界", count: 200))])])
        let doc = try OrderDocument(shop: shop, data: data)
        XCTAssertTrue(try doc.downloadPath().hasPrefix("_action/document/" + id + "/"))
        XCTAssertFalse(doc.filename.contains("/")); XCTAssertLessThan(doc.filename.utf8.count + 33, 255)
        let pdf = try XCTUnwrap(PDFDocument(data: OrderDocument.demoPDF(number: "#1001")))
        XCTAssertEqual(pdf.pageCount, 1); XCTAssertTrue(pdf.string?.contains("not a real invoice") == true)
        var invalid = data.object!; invalid["deepLinkCode"] = .string("../private")
        XCTAssertThrowsError(try OrderDocument(shop: shop, data: .object(invalid)).downloadPath())
    }
    func testLiveOriginalDocumentDownload() async throws {
        guard ProcessInfo.processInfo.environment["SHOPDECK_DOCUMENT_LIVE"] == "1" else {
            throw XCTSkip("Opt in for the isolated 127.0.0.1:18888 document fixture.")
        }
        var shop = Shop(name: "Document verification", url: "http://127.0.0.1:18888", environment: "Lokal")
        shop.containerName = "shopdeck-verification-1106"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try WorkspaceStore(directory: directory)
        let credentials = MemoryCredentials()
        let client = ShopwareClient(store: store, credentials: credentials)
        let integration = try await client.bootstrapLocal(shop)
        try credentials.save(integration, for: shop.id)

        let base = try XCTUnwrap(URL(string: shop.url + "/api/"))
        var auth = URLRequest(url: base.appendingPathComponent("oauth/token"))
        auth.httpMethod = "POST"
        auth.setValue("application/json", forHTTPHeaderField: "Content-Type")
        auth.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "client_credentials", "client_id": integration.clientID, "client_secret": integration.clientSecret
        ])
        let (authBytes, authResponse) = try await URLSession.shared.data(for: auth)
        XCTAssertEqual((authResponse as? HTTPURLResponse)?.statusCode, 200)
        let bearer = try XCTUnwrap(JSONDecoder().decode(JSONValue.self, from: authBytes)["access_token"].string)

        let orders = try await client.search(shop, entity: "order", limit: 20)
        let orderIDs = orders.rows.compactMap { $0["id"].string }
        let original = try await client.orderDocuments(shop, orderIDs: orderIDs)
        let usedOrders = Set(original.documents.map(\.orderID))
        let orderID = try XCTUnwrap(orderIDs.first { !usedOrders.contains($0) })
        let expectedTypes = ["invoice", "delivery_note"]
        var generated: [OrderDocument] = []

        func removeGenerated() async throws {
            let remaining = try await client.orderDocuments(shop, orderIDs: [orderID])
            for document in remaining.documents where expectedTypes.contains(document.type) {
                _ = try await client.adminRequest(shop, request: .init(method: "DELETE", path: "document/" + document.documentID))
            }
        }

        do {
            for type in expectedTypes {
                let operation: JSONValue = .object(["orderId": .string(orderID), "fileType": .string("pdf")])
                _ = try await client.adminRequest(shop, request: .init(
                    method: "POST", path: "_action/order/document/" + type + "/create", body: .array([operation])
                ))
            }
            generated = try await client.orderDocuments(shop, orderIDs: [orderID]).documents
            XCTAssertEqual(Set(generated.map(\.type)), Set(expectedTypes))
            XCTAssertEqual(generated.count, expectedTypes.count)
            for document in generated {
                var request = URLRequest(url: base.appendingPathComponent(try document.downloadPath()))
                request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization")
                request.setValue("application/pdf", forHTTPHeaderField: "Accept")
                let (original, response) = try await URLSession.shared.data(for: request)
                XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
                let downloaded = try await client.downloadDocument(document)
                XCTAssertEqual(downloaded, original)
                let preview = try XCTUnwrap(PDFDocument(data: downloaded))
                XCTAssertGreaterThan(preview.pageCount, 0)
                XCTAssertTrue(try XCTUnwrap(preview.string).contains(document.number))
                XCTAssertFalse(preview.string?.contains("SAMPLE DOCUMENT") == true)
                print("Shopware generated \(document.type), verified \(downloaded.count) identical PDF bytes in Shopdeck and a readable PDFKit preview.")
            }
        } catch {
            try? await removeGenerated()
            throw error
        }
        try await removeGenerated()
        let after = try await client.orderDocuments(shop, orderIDs: [orderID])
        XCTAssertTrue(after.documents.isEmpty)
    }

}
