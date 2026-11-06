import Foundation

public struct RecordBookmark: Codable, Identifiable, Equatable, Sendable {
    public let shopID: UUID
    public let entity: String
    public let recordID: String
    public var title: String
    public var reference: String
    public let createdAt: Date
    public var id: String { shopID.uuidString + ":" + entity + ":" + recordID }
    public init(shopID: UUID, entity: String, recordID: String, title: String, reference: String = "", createdAt: Date = Date()) throws {
        guard ["product", "order", "customer"].contains(entity) else { throw ShopdeckError.message("Unbekannte Datenart.") }
        self.shopID = shopID; self.entity = entity; self.recordID = try Validation.entityID(recordID)
        self.title = String(title.prefix(200)); self.reference = String(reference.prefix(100)); self.createdAt = createdAt
    }
}
extension WorkspaceStore {
    public func toggleBookmark(_ item: RecordBookmark) throws {
        try updateWorkbench { state in
            var items = state.bookmarks ?? []
            if items.contains(where: { $0.id == item.id }) { items.removeAll { $0.id == item.id } }
            else { items.append(item) }
            state.bookmarks = items
        }
    }
}
