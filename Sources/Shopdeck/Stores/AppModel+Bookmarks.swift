import Foundation
import ShopdeckCore

extension AppModel {
    var bookmarks: [RecordBookmark] {
        let connected = Set(workspace.shops.map(\.id))
        return (workbench.bookmarks ?? []).filter { connected.contains($0.shopID) }.sorted { $0.createdAt > $1.createdAt }
    }
    func isBookmarked(_ record: ShopRecord) -> Bool { (workbench.bookmarks ?? []).contains { $0.shopID == record.shop.id && $0.entity == record.entity && $0.recordID == record.data["id"].string?.lowercased() } }
    func toggleBookmark(_ record: ShopRecord) {
        let id = record.data["id"].string ?? ""
        let title: String
        switch record.entity {
        case "order": title = "#" + (record.data["orderNumber"].string ?? id)
        case "customer": title = [record.data["firstName"].string, record.data["lastName"].string].compactMap { $0 }.joined(separator: " ")
        default: title = record.data.at("name").string ?? id
        }
        let reference = record.data["productNumber"].string ?? record.data["orderNumber"].string ?? record.data["customerNumber"].string ?? ""
        do {
            let item = try RecordBookmark(shopID: record.shop.id, entity: record.entity, recordID: id, title: title.isEmpty ? id : title, reference: reference)
            let removing = isBookmarked(record); try store.toggleBookmark(item); reload(); notice = T(removing ? "Lesezeichen entfernt" : "Lesezeichen gespeichert")
        } catch { self.error = error.localizedDescription }
    }
    func openBookmark(_ item: RecordBookmark) {
        guard let shop = workspace.shops.first(where: { $0.id == item.shopID }) else { error = T("Dieser Shop ist nicht mehr verbunden."); return }
        editingRecord = .init(shop: shop, data: .object(["id": .string(item.recordID)]), entity: item.entity)
    }
    var recordDateRange: RecordDateRange? {
        let field = RecordDateRange.field(for: destination.entity)
        return activeFilters.first { $0.field == field && $0.operation == "dateRange" }.flatMap { RecordDateRange(rawValue: $0.value) }
    }
    func setRecordDateRange(_ value: RecordDateRange?) {
        let field = RecordDateRange.field(for: destination.entity)
        var filters = activeFilters.filter { !($0.field == field && $0.operation == "dateRange") }
        if let value { var filter = value.filter(field: field); filter.name = T(value.title); filters.append(filter) }
        activeFilters = filters
    }
}
