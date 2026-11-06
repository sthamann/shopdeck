import Foundation

public enum ProductChangeStatus: String, Codable, Sendable { case applying, applied, uncertain, failed, undone }
public struct ProductChangeRecord: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var operationID: UUID
    public var shopID: UUID
    public var shopName: String
    public var isDemo: Bool
    public var productID: String
    public var productName: String
    public var before: [String: JSONValue]
    public var after: [String: JSONValue]
    public var requested:[String:JSONValue]?
    public var origin: String
    public var status: ProductChangeStatus = .applying
    public var createdAt: Date = Date()
    public var completedAt: Date?
    public var error: String?
    public var undoOfID: UUID?
    public init(shop: Shop, productID: String, productName: String, before: [String: JSONValue], after: [String: JSONValue], origin: String, operationID: UUID = UUID(), undoOfID: UUID? = nil) {
        self.shopID = shop.id; self.shopName = shop.name; self.isDemo = shop.isDemo; self.productID = productID; self.productName = productName; self.before = before; self.after = after; self.origin = origin; self.operationID = operationID; self.undoOfID = undoOfID
    }
}
public struct ProductJournal: Codable, Sendable {
    public var changes: [ProductChangeRecord] = []
    public init() {}
}
public protocol ProductGateway: Sendable {
    func detail(_ shop: Shop, entity: String, id: String) async throws -> JSONValue
    func updateProduct(_ shop: Shop, id: String, changes: [String: JSONValue]) async throws
    func restoreProduct(_ shop: Shop, id: String, changes: [String: JSONValue]) async throws
}

public enum BulkStockMode: String, Sendable, CaseIterable { case set, adjust }
public struct BulkProductDraft: Sendable {
    public var stock: Int?
    public var stockMode: BulkStockMode
    public var active: Bool?
    public init(stock: Int? = nil, stockMode: BulkStockMode = .set, active: Bool? = nil) { self.stock = stock; self.stockMode = stockMode; self.active = active }
    public func changes(for product: JSONValue) throws -> [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        if let stock {
            let n: Int
            if stockMode == .adjust {
                guard let current = product["stock"].number, current.isFinite, (0...2147483647).contains(current) else { throw ShopdeckError.message("Der aktuelle Bestand ist nicht lesbar.") }
                let (value, overflow) = Int(current).addingReportingOverflow(stock)
                guard !overflow else { throw ShopdeckError.message("Die Bestandsänderung ist zu groß.") }
                n = value
            } else { n = stock }
            result["stock"] = .number(Double(n))
        }
        if let active { result["active"] = .bool(active) }
        return try Validation.productChanges(result)
    }
}
public struct BulkProductPlan: Identifiable, Sendable {
    public var id: String { shop.id.uuidString + ":" + productID }
    public let shop: Shop
    public let productID: String
    public let productName: String
    public let before: [String: JSONValue]
    public let after: [String: JSONValue]
}

/// All app writes share this journal. A write is recorded before it reaches the shop.
public actor ProductChangeService {
    private let store: WorkspaceStore
    private let gateway: any ProductGateway
    private var activeProducts: Set<String> = []
    public init(store: WorkspaceStore, gateway: any ProductGateway) { self.store = store; self.gateway = gateway }
    public func preview(_ shop: Shop, id: String, draft: BulkProductDraft) async throws -> BulkProductPlan {
        let id = try Validation.entityID(id)
        let current = try await gateway.detail(shop, entity: "product", id: id)
        let changes = try draft.changes(for: current).filter { current[$0.key] != $0.value }
        return BulkProductPlan(shop: shop, productID: id, productName: current.at("name").string ?? current["translated"]["name"].string ?? id, before: Self.values(current, keys: changes.keys), after: changes)
    }
    @discardableResult public func apply(_ shop: Shop, id: String, changes: [String: JSONValue], origin: String, operationID: UUID = UUID(), expectedBefore: [String: JSONValue]? = nil) async throws -> ProductChangeRecord? {
        let validated = try Validation.productChanges(changes)
        return try await write(shop, id: id, changes: validated, origin: origin, operationID: operationID, expectedBefore: expectedBefore, undoOfID: nil)
    }
    public func undo(_ id: UUID, shop: Shop) async throws -> ProductChangeRecord? {
        guard let original = try store.readProductJournal().changes.first(where: { $0.id == id }), original.shopID == shop.id, original.status == .applied, original.undoOfID == nil else { throw ShopdeckError.message("Diese Änderung kann nicht rückgängig gemacht werden.") }
        let restoration = try Validation.productRestoration(original.before)
        return try await write(shop, id: original.productID, changes: restoration, origin: "undo", operationID: UUID(), expectedBefore: original.after, undoOfID: original.id)
    }
    public func reconcile(_ id: UUID, shop: Shop) async throws -> ProductChangeRecord {
        guard var entry = try store.readProductJournal().changes.first(where: { $0.id == id }), entry.shopID == shop.id, [.applying, .uncertain].contains(entry.status) else { throw ShopdeckError.message("Diese Änderung benötigt keine erneute Prüfung.") }
        let key = shop.id.uuidString + ":" + entry.productID
        guard !activeProducts.contains(key) else { throw ShopdeckError.message("Die Änderung läuft noch.") }
        let current = try await gateway.detail(shop, entity: "product", id: entry.productID)
        if Self.values(current, keys: entry.after.keys) == entry.after { entry.status = .applied; entry.error = nil; entry.completedAt = Date() }
        else if Self.values(current, keys: entry.before.keys) == entry.before { entry.status = .failed; entry.error = "Die ursprünglichen Werte sind weiterhin im Shop gespeichert."; entry.completedAt = Date() }
        else { entry.status = .uncertain; entry.error = "Der Shop enthält abweichende Werte. Bitte prüfe das Produkt direkt." }
        try persist(entry)
        return entry
    }
    private func write(_ shop: Shop, id: String, changes: [String: JSONValue], origin: String, operationID: UUID, expectedBefore: [String: JSONValue]?, undoOfID: UUID?) async throws -> ProductChangeRecord? {
        let id = try Validation.entityID(id), key = shop.id.uuidString + ":" + id
        if let prior=try store.readProductJournal().changes.first(where:{$0.operationID==operationID}) {guard prior.shopID==shop.id,prior.productID==id,(prior.requested ?? prior.after)==changes else{throw ShopdeckError.message("Die Vorgangs ID wurde bereits für andere Werte verwendet.")};guard [.applied,.undone].contains(prior.status)else{throw ShopdeckError.message("Prüfe zuerst das Ergebnis dieses Vorgangs im Änderungsverlauf.")};return prior}
        guard !activeProducts.contains(key) else { throw ShopdeckError.message("Für dieses Produkt läuft bereits eine Änderung.") }
        activeProducts.insert(key); defer { activeProducts.remove(key) }
        let current = try await gateway.detail(shop, entity: "product", id: id)
        if let expectedBefore, Self.values(current, keys: expectedBefore.keys) != expectedBefore { throw ShopdeckError.message("Das Produkt wurde inzwischen geändert. Lade eine neue Vorschau. Beim Rückgängigmachen werden neuere Änderungen nicht überschrieben.") }
        let actualChanges = changes.filter { current[$0.key] != $0.value }
        guard !actualChanges.isEmpty else { return nil }
        var entry = ProductChangeRecord(shop: shop, productID: id, productName: current.at("name").string ?? current["translated"]["name"].string ?? id, before: Self.values(current, keys: actualChanges.keys), after: actualChanges, origin: origin, operationID: operationID, undoOfID: undoOfID)
        entry.requested=changes
        try store.updateProductJournal { journal in
            guard !journal.changes.contains(where:{$0.operationID==operationID})else{throw ShopdeckError.message("Dieser Vorgang wurde bereits protokolliert.")}
            guard !journal.changes.contains(where: { $0.shopID == shop.id && $0.productID == id && [.applying, .uncertain].contains($0.status) }) else { throw ShopdeckError.message("Prüfe zuerst den offenen Eintrag für dieses Produkt im Änderungsverlauf.") }
            if let undoOfID { guard journal.changes.first(where: { $0.id == undoOfID })?.status == .applied else { throw ShopdeckError.message("Diese Änderung wurde bereits zurückgenommen.") } }
            journal.changes.append(entry)
        }
        var failure: String?
        do {
            if undoOfID == nil { try await gateway.updateProduct(shop, id: id, changes: actualChanges) }
            else { try await gateway.restoreProduct(shop, id: id, changes: actualChanges) }
        } catch { failure = error.localizedDescription }
        do {
            let observed = try await gateway.detail(shop, entity: "product", id: id)
            if Self.values(observed, keys: actualChanges.keys) == actualChanges { entry.status = .applied; entry.completedAt = Date() }
            else { entry.status = .uncertain; entry.error = failure ?? "Die gelesenen Werte bestätigen die Änderung noch nicht." }
        } catch { entry.status = .uncertain; entry.error = failure ?? error.localizedDescription }
        try persist(entry)
        return entry
    }
    private func persist(_ entry: ProductChangeRecord) throws {
        try store.updateProductJournal { journal in
            guard let i = journal.changes.firstIndex(where: { $0.id == entry.id }) else { throw ShopdeckError.message("Der Eintrag im Änderungsverlauf fehlt.") }
            journal.changes[i] = entry
            if entry.status == .applied, let original = entry.undoOfID, let index = journal.changes.firstIndex(where: { $0.id == original }) { journal.changes[index].status = .undone }
        }
    }
    private static func values<S: Sequence>(_ value: JSONValue, keys: S) -> [String: JSONValue] where S.Element == String { Dictionary(uniqueKeysWithValues: keys.map { ($0, value[$0]) }) }
}
