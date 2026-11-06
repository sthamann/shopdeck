import Foundation

public struct SavedView: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID = UUID()
    public var name: String
    public var destination: String
    public var shopID: UUID?
    public var query: String
    public var lowStock: Bool
    public var filters: [RecordFilter]?
    public var channelKey:String?
    public var currency:String?
    public var sort:[RecordSort]?
    public var status: String
    public init(name: String, destination: String, shopID: UUID?, query: String = "", lowStock: Bool = false, status: String = "all") {
        self.name = name; self.destination = destination; self.shopID = shopID; self.query = query; self.lowStock = lowStock; self.status = status
    }
}
public struct Workbench: Codable, Sendable {
    public var savedViews: [SavedView] = []
    public var lists: [String: ListConfiguration]?
    public var dashboard: DashboardConfiguration?
    public init() {}
}

public enum SearchFilters {
    public static func criteria(entity: String, lowStock: Bool, status: String) throws -> [JSONValue] {
        var filters: [JSONValue] = []
        if lowStock && entity == "product" {
            filters.append(.object(["type": .string("range"), "field": .string("stock"), "parameters": .object(["lte": .number(5)])]))
        }
        guard status != "all" else { return filters }
        let field: String, value: JSONValue
        if entity == "order", ["open", "in_progress", "completed", "cancelled"].contains(status) {
            field = "stateMachineState.technicalName"; value = .string(status)
        } else if ["product", "customer"].contains(entity), ["active", "inactive"].contains(status) {
            field = "active"; value = .bool(status == "active")
        } else { throw ShopdeckError.message("Der gewählte Status passt nicht zu dieser Ansicht.") }
        filters.append(.object(["type": .string("equals"), "field": .string(field), "value": value]))
        return filters
    }
    public static func matches(_ row: JSONValue, entity: String, status: String) -> Bool {
        guard status != "all" else { return true }
        if entity == "order" { return row["stateMachineState"]["technicalName"].string == status }
        return row["active"].bool == (status == "active")
    }
}
