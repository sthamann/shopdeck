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
        guard ProcessInfo.processInfo.environment["SHOPDECK_DOCUMENT_LIVE"] == "1" else { throw XCTSkip("Opt in for the isolated local document fixture.") }
        let shop = try XCTUnwrap(try WorkspaceStore().read().shops.first { $0.url == "http://127.0.0.1:18888" })
        let helper = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Shopdeck.app/Contents/Helpers/shopdeck-keychain")
        let process = Process(), pipe = Pipe(); process.executableURL = helper; process.arguments = ["load", shop.id.uuidString]; process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run(); let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        struct Reply: Decodable { let status: Int32; let credentials: Credentials? }
        let reply = try JSONDecoder().decode(Reply.self, from: data); XCTAssertEqual(reply.status, 0)
        let credentials = MemoryCredentials(); try credentials.save(XCTUnwrap(reply.credentials), for: shop.id)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = ShopwareClient(store: try WorkspaceStore(directory: directory), credentials: credentials)
        let orderResponse = try await client.search(shop, entity: "order", limit: 1)
        let order = try XCTUnwrap(orderResponse.rows.first), orderID = try XCTUnwrap(order["id"].string)
        let types = try await client.adminRequest(shop, request: .init(method: "POST", path: "search/document-type", body: .object(["filter": .array([.object(["type": .string("equals"), "field": .string("technicalName"), "value": .string("invoice")])]), "limit": .number(1)])))
        let typeID = try XCTUnwrap(types["data"].array.first?["id"].string)
        let mediaID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased(), docID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let pdf = OrderDocument.demoPDF(number: "SHOPDECK-VERIFICATION")
        var mediaCreated = false, docCreated = false
        do {
            _ = try await client.adminRequest(shop, request: .init(method: "POST", path: "media", body: .object(["id": .string(mediaID)]))); mediaCreated = true
            _ = try await client.uploadBinary(shop, path: "_action/media/" + mediaID + "/upload", data: pdf, contentType: "application/pdf", query: ["extension": "pdf", "fileName": "shopdeck-document-verification-" + mediaID])
            var payload: [String: JSONValue] = ["id": .string(docID), "orderId": .string(orderID), "documentTypeId": .string(typeID), "documentMediaFileId": .string(mediaID), "static": .bool(true), "deepLinkCode": .string(mediaID), "config": .object(["documentNumber": .string("SHOPDECK-VERIFICATION")])]
            if let version = order["versionId"].string { payload["orderVersionId"] = .string(version) }
            _ = try await client.adminRequest(shop, request: .init(method: "POST", path: "document", body: .object(payload))); docCreated = true
            let page = try await client.orderDocuments(shop, orderIDs: [orderID])
            let document = try XCTUnwrap(page.documents.first { $0.documentID == docID })
            let downloaded = try await client.downloadDocument(document)
            XCTAssertEqual(downloaded, pdf); XCTAssertEqual(PDFDocument(data: downloaded)?.pageCount, 1)
            print("Original PDF uploaded as isolated static fixture, listed through document search, downloaded byte for byte, and parsed with PDFKit.")
        } catch {
            if docCreated { _ = try? await client.adminRequest(shop, request: .init(method: "DELETE", path: "document/" + docID)) }
            if mediaCreated { _ = try? await client.adminRequest(shop, request: .init(method: "DELETE", path: "media/" + mediaID)) }
            throw error
        }
        _ = try await client.adminRequest(shop, request: .init(method: "DELETE", path: "document/" + docID))
        let remainingMedia = try await client.adminRequest(shop, request: .init(method: "POST", path: "search/media", body: .object(["ids": .array([.string(mediaID)]), "limit": .number(1)])))
        if !remainingMedia["data"].array.isEmpty { _ = try await client.adminRequest(shop, request: .init(method: "DELETE", path: "media/" + mediaID)) }
        let after = try await client.orderDocuments(shop, orderIDs: [orderID]); XCTAssertFalse(after.documents.contains { $0.documentID == docID })
    }

}
