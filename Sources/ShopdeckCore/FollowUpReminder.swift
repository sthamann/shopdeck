import Foundation

public struct FollowUpReminder: Equatable, Sendable, Identifiable {
    public static let prefix = "shopdeck.followup."
    public var id: String
    public var followUpID: UUID
    public var dueAt: Date
    public var recordTitle: String
    public var shopName: String
    public static func plan(items: [RecordFollowUp], shops: [Shop], now: Date = Date()) -> [Self] {
        items.compactMap { item in
            guard item.reminderEnabled == true, item.completedAt == nil, let due = item.dueAt, due > now, let shop = shops.first(where: { $0.id == item.shopID }) else { return nil }
            return Self(id: prefix + item.id.uuidString, followUpID: item.id, dueAt: due, recordTitle: item.title, shopName: shop.name)
        }.sorted { $0.dueAt < $1.dueAt }
    }
}
