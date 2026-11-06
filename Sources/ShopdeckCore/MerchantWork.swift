import Foundation

public enum MerchantFocus: String, CaseIterable, Identifiable, Sendable {
    case overdueOrders, processingOrders, lowStock, soldOut, missingImage, missingDescription
    public var id: String { rawValue }
    public var entity: String { [.overdueOrders, .processingOrders].contains(self) ? "order" : "product" }
    public var title: String {
        switch self {
        case .overdueOrders: return "Lange offene Bestellungen"
        case .processingOrders: return "Bestellungen in Bearbeitung"
        case .lowStock: return "Bestand nachbestellen"
        case .soldOut: return "Aktiv und ausverkauft"
        case .missingImage: return "Produktbild fehlt"
        case .missingDescription: return "Beschreibung fehlt"
        }
    }
    public var icon: String {
        switch self {
        case .overdueOrders: return "clock.badge.exclamationmark"
        case .processingOrders: return "shippingbox"
        case .lowStock: return "arrow.down.to.line"
        case .soldOut: return "exclamationmark.triangle"
        case .missingImage: return "photo"
        case .missingDescription: return "text.alignleft"
        }
    }
    public func filters(stockThreshold: Int = 10, overdueHours: Int = 48, now: Date = Date()) -> [RecordFilter] {
        func filter(_ field: String, _ value: String, _ operation: String = "equals") -> RecordFilter {
            .init(name: title, field: field, operation: operation, value: value)
        }
        switch self {
        case .overdueOrders:
            return [filter("stateMachineState.technicalName", "open"), filter("orderDateTime", ISO8601DateFormatter().string(from: now.addingTimeInterval(-Double(min(max(overdueHours, 1), 8760)) * 3600)), "lt")]
        case .processingOrders: return [filter("stateMachineState.technicalName", "in_progress")]
        case .lowStock: return [filter("active", "true"), filter("stock", "0", "gt"), filter("stock", String(min(max(stockThreshold, 1), 100000)), "lte")]
        case .soldOut: return [filter("active", "true"), filter("stock", "0", "lte")]
        case .missingImage: return [filter("active", "true"), filter("parentId", "", "isNull"), filter("coverId", "", "isNull")]
        case .missingDescription: return [filter("active", "true"), filter("parentId", "", "isNull"), filter("description", "", "empty")]
        }
    }
}

/// Private, local follow ups. This data is not part of the MCP workspace or Shopware writes.
public struct RecordFollowUp: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var shopID: UUID
    public var entity: String
    public var recordID: String
    public var title: String
    public var reference: String
    public var note: String
    public var dueAt: Date?
    public var createdAt: Date
    public var completedAt: Date?
    public init(id: UUID = UUID(), shopID: UUID, entity: String, recordID: String, title: String, reference: String = "", note: String = "", dueAt: Date? = nil, createdAt: Date = Date()) throws {
        guard ["product", "order", "customer"].contains(entity) else { throw ShopdeckError.message("Unbekannte Datenart.") }
        self.id = id; self.shopID = shopID; self.entity = entity; self.recordID = try Validation.entityID(recordID).lowercased()
        self.title = String(title.prefix(300)); self.reference = String(reference.prefix(100)); self.note = String(note.prefix(4000)); self.dueAt = dueAt; self.createdAt = createdAt
    }
    public func isDue(at date: Date = Date()) -> Bool { completedAt == nil && dueAt.map { $0 <= date } == true }
}

extension WorkspaceStore {
    public func saveFollowUp(_ item: RecordFollowUp) throws {
        let completed = item.completedAt
        var item = try RecordFollowUp(id: item.id, shopID: item.shopID, entity: item.entity, recordID: item.recordID, title: item.title, reference: item.reference, note: item.note, dueAt: item.dueAt, createdAt: item.createdAt)
        item.completedAt = completed
        try updateWorkbench { state in
            var values = state.followUps ?? []
            if let index = values.firstIndex(where: { $0.shopID == item.shopID && $0.entity == item.entity && $0.recordID.lowercased() == item.recordID.lowercased() }) {
                var copy = item; copy.id = values[index].id; copy.createdAt = values[index].createdAt; values[index] = copy
            } else {
                guard values.count < 10000 else { throw ShopdeckError.message("Die maximale Anzahl lokaler Wiedervorlagen ist erreicht.") }
                values.append(item)
            }
            state.followUps = values
        }
    }
}

public enum RecordCSV {
    /// UTF 8 BOM for spreadsheet apps, stable columns and RFC 4180 quoting.
    public static func encode(rows: [FederatedRecord], columns: [RecordColumn]) -> Data {
        func quote(_ value: String) -> String {
            let first = value.trimmingCharacters(in: .whitespacesAndNewlines).first
            let guarded = first.map { "=+-@".contains($0) } == true || value.hasPrefix("\t") || value.hasPrefix("\r") || value.hasPrefix("\n")
            let safe = guarded ? "'" + value : value
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var lines = [columns.map { quote($0.title) }.joined(separator: ",")]
        for row in rows {
            lines.append(columns.map { column in
                let value = column.field == "shop" ? JSONValue.string(row.shop.name) : row.data.at(column.field)
                let text: String
                switch value {
                case .string(let s): text = s
                case .number(let n): text = String(n)
                case .bool(let b): text = b ? "true" : "false"
                case .null: text = ""
                default: text = value.pretty
                }
                return quote(text)
            }.joined(separator: ","))
        }
        return Data((["\u{feff}"] + [lines.joined(separator: "\r\n") + "\r\n"]).joined().utf8)
    }
}
