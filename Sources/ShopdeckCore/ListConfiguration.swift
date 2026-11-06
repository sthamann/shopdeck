import Foundation

public struct RecordColumn: Codable, Identifiable, Equatable, Sendable {
    public var id: String { field }
    public var field: String
    public var title: String
    public var width: Double
    public init(_ field: String, _ title: String, width: Double = 160) { self.field = field; self.title = title; self.width = width }
}
public struct RecordFilter: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var field: String
    public var operation: String
    public var value: String
    public init(name: String, field: String, operation: String = "equals", value: String) { self.name = name; self.field = field; self.operation = operation; self.value = value }
    public func criteria(now: Date = Date(), calendar: Calendar = .current) throws -> JSONValue {
        guard field.range(of: "^[A-Za-z][A-Za-z0-9_.]*$", options: .regularExpression) != nil, field.count <= 150 else { throw ShopdeckError.message("Ungültiger Feldname.") }
        let leaf = field.split(separator: ".").last.map(String.init) ?? field
        let numeric = ["stock", "availableStock", "amountTotal", "amountNet", "shippingTotal", "gross", "net", "weight", "minPurchase", "purchaseSteps", "orderCount", "orderTotalAmount"]
        let typed: JSONValue = ["active", "guest"].contains(leaf) && ["true", "false"].contains(value) ? .bool(value == "true") : numeric.contains(leaf) ? Double(value).map(JSONValue.number) ?? .string(value) : .string(value)
        switch operation {
        case "dateRange":
            guard ["createdAt", "updatedAt", "orderDateTime"].contains(field), let range = RecordDateRange(rawValue: value) else { throw ShopdeckError.message("Ungültiger Zeitraum.") }
            let interval = range.interval(now: now, calendar: calendar), formatter = ISO8601DateFormatter()
            return .object(["type": .string("range"), "field": .string(field), "parameters": .object(["gte": .string(formatter.string(from: interval.start)), "lt": .string(formatter.string(from: interval.end))])])
        case "isNull": return .object(["type": .string("equals"), "field": .string(field), "value": .null])
        case "empty": return .object(["type": .string("multi"), "operator": .string("OR"), "queries": .array([.object(["type": .string("equals"), "field": .string(field), "value": .null]), .object(["type": .string("equals"), "field": .string(field), "value": .string("")])])])
        case "equals", "contains": return .object(["type": .string(operation), "field": .string(field), "value": operation == "contains" ? .string(value) : typed])
        case "lte", "gte", "lt", "gt": return .object(["type": .string("range"), "field": .string(field), "parameters": .object([operation: typed])])
        default: throw ShopdeckError.message("Unbekannter Vergleich.")
        }
    }
    public func matches(_ row: JSONValue, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        func values(_ node:JSONValue,_ path:[Substring])->[JSONValue]{guard let first=path.first else{return [node]};if case .array(let array)=node,Int(first)==nil{return array.flatMap{values($0,path)}};return values(node.at(String(first)),Array(path.dropFirst()))}
        return values(row,field.split(separator:".")).contains{matchesValue($0, now: now, calendar: calendar)}
    }
    private func matchesValue(_ current:JSONValue, now: Date, calendar: Calendar)->Bool {
        if operation == "dateRange" {
            guard let range = RecordDateRange(rawValue: value), let text = current.string else { return false }
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text) else { return false }
            let interval = range.interval(now: now, calendar: calendar); return date >= interval.start && date < interval.end
        }
        if operation == "isNull" { return current == .null }
        if operation == "empty" { return current == .null || current.string == "" }
        if operation == "contains" { return current.displayString.localizedCaseInsensitiveContains(value) }
        if operation == "equals" { if let b = current.bool { return String(b) == value }; if let n = current.number, let target = Double(value) { return n == target }; return current.string == value }
        let order: ComparisonResult
        if let n = current.number, let target = Double(value) { order = n < target ? .orderedAscending : n > target ? .orderedDescending : .orderedSame }
        else if let text = current.string { order = text.compare(value) } else { return false }
        switch operation { case "lte": return order != .orderedDescending; case "gte": return order != .orderedAscending; case "lt": return order == .orderedAscending; case "gt": return order == .orderedDescending; default: return false }
    }
}
public struct ListConfiguration: Codable, Equatable, Sendable {
    public var columns: [RecordColumn]
    public var showProductThumbnails:Bool?
    public var filters: [RecordFilter]
    public init(columns: [RecordColumn], filters: [RecordFilter] = []) { self.columns = columns; self.filters = filters }
    public static func standard(_ entity: String) -> Self {
        let catalog = fields(entity)
        let defaults: [String] = entity == "product" ? ["shop", "name", "productNumber", "stock", "active"] : entity == "order" ? ["shop", "orderNumber", "orderDateTime", "amountTotal", "stateMachineState.technicalName"] : ["shop", "firstName", "lastName", "email", "customerNumber"]
        return .init(columns: defaults.compactMap { field in catalog.first { $0.field == field } })
    }
    public static func fields(_ entity: String) -> [RecordColumn] {
        let shared = [RecordColumn("shop", "Shop", width: 150), RecordColumn("id", "Shopware ID", width: 250), RecordColumn("createdAt", "Erstellt am"), RecordColumn("updatedAt", "Aktualisiert am")]
        switch entity {
        case "product": return shared + [.init("name", "Name", width: 260), .init("productNumber", "Produktnummer"), .init("stock", "Bestand", width: 95), .init("availableStock", "Verfügbarer Bestand"), .init("active", "Aktiv", width: 90), .init("price.0.gross", "Bruttopreis"), .init("price.0.net", "Nettopreis"), .init("manufacturer.name", "Hersteller"), .init("ean", "EAN"), .init("manufacturerNumber", "Herstellernummer"), .init("weight", "Gewicht"), .init("minPurchase", "Mindestabnahme"), .init("purchaseSteps", "Abnahmeschritte")]
        case "order": return shared + [.init("orderNumber", "Bestellnummer"), .init("orderDateTime", "Datum", width: 180), .init("amountTotal", "Gesamt", width: 120), .init("amountNet", "Nettobetrag"), .init("shippingTotal", "Versandkosten"), .init("currency.isoCode", "Währung", width: 90), .init("stateMachineState.technicalName", "Status"), .init("orderCustomer.email", "E Mail", width: 230), .init("orderCustomer.firstName", "Vorname"), .init("orderCustomer.lastName", "Nachname"), .init("salesChannel.name", "Verkaufskanal")]
        default: return shared + [.init("firstName", "Vorname"), .init("lastName", "Nachname"), .init("email", "E Mail", width: 240), .init("customerNumber", "Kundennummer"), .init("company", "Firma"), .init("active", "Aktiv", width: 90), .init("guest", "Gast", width: 80), .init("orderCount", "Bestellungen", width: 110), .init("orderTotalAmount", "Bestellwert"), .init("group.name", "Kundengruppe"), .init("defaultBillingAddress.city", "Ort"), .init("defaultBillingAddress.country.iso", "Land")]
        }
    }
}
extension JSONValue {
    public func at(_ path: String) -> JSONValue { path.split(separator: ".").reduce(self) { node, key in if let index = Int(key) { return node.array.indices.contains(index) ? node.array[index] : .null }; let raw=node[String(key)]; return raw == .null && key != "translated" ? node["translated"][String(key)] : raw } }

    public var displayString: String { switch self { case .string(let s): return s; case .number(let n): return n.formatted(); case .bool(let b): return b ? "true" : "false"; case .null: return "–"; case .array(let a): return "\(a.count)"; case .object: return pretty } }
}
