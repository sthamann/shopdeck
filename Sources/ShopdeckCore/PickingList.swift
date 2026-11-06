import Foundation
import CoreGraphics
import CoreText

public struct PickingOrder: Identifiable, Sendable, Equatable {
    public let shop: Shop
    public let orderID: String
    public let number: String
    public let state: String
    public var id: String { shop.id.uuidString + ":" + orderID }
    public init(shop: Shop, data: JSONValue) throws {
        self.shop = shop; orderID = try Validation.entityID(data["id"].string ?? "")
        number = data["orderNumber"].string ?? String(orderID.prefix(8))
        guard let status = data["stateMachineState"]["technicalName"].string, !status.isEmpty else { throw ShopdeckError.message("Der Bestellstatus konnte nicht geprüft werden.") }; state = status
    }
}
public struct PickingAllocation: Identifiable, Sendable, Equatable {
    public let order: PickingOrder
    public var quantity: Int
    public var id: String { order.id }
}
public struct PickingItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let shop: Shop
    public let sku: String
    public let title: String
    public var quantity: Int
    public var allocations: [PickingAllocation]
    public var shopName: String { shop.name }
    public var orderSummary: String { allocations.map { "#" + $0.order.number + " × " + String($0.quantity) }.joined(separator: ", ") }
}
public struct PickingList: Sendable {
    public var orders: [PickingOrder]
    public var items: [PickingItem]
    public var excludedOrders: Int
    public var excludedLines: Int
    public let loadedAt: Date
    public var units: Int { items.reduce(0) { $0 + $1.quantity } }
    public static func assemble(orders: [PickingOrder], lines: [(Shop, JSONValue)], now: Date = Date()) throws -> Self {
        guard Set(orders.map(\.id)).count == orders.count else { throw ShopdeckError.message("Die Bestellauswahl enthält doppelte IDs.") }
        let eligible = Dictionary(uniqueKeysWithValues: orders.filter { $0.state != "cancelled" }.map { ($0.id, $0) })
        var items: [String: PickingItem] = [:], excluded = 0, seen = Set<String>()
        for (shop, row) in lines {
            let lineID = try Validation.entityID(row["id"].string ?? "")
            guard seen.insert(shop.id.uuidString + ":" + lineID).inserted else { continue }
            guard let orderID = row["orderId"].string, let order = eligible[shop.id.uuidString + ":" + orderID] else { continue }
            guard row["type"].string == "product", row["good"].bool == true else { excluded += 1; continue }
            guard let quantity = row["quantity"].number, quantity.isFinite, quantity >= 0, quantity <= 1000000000, quantity.rounded() == quantity else { throw ShopdeckError.message("Eine Bestellposition hat keine gültige Stückzahl.") }
            guard quantity > 0 else { excluded += 1; continue }
            let sku = row["payload"]["productNumber"].string ?? ""
            let productID = row["productId"].string ?? row["referencedId"].string ?? row["identifier"].string ?? ""
            let identity = productID.isEmpty ? (sku.isEmpty ? lineID : sku) : productID
            // Shop, product and historical SKU are part of the identity. Different variants and shops never share a bin.
            let key = [shop.id.uuidString, identity, sku].map { String($0.utf8.count) + ":" + $0 }.joined()
            var item = items[key] ?? PickingItem(id: key, shop: shop, sku: sku, title: row["label"].string ?? sku, quantity: 0, allocations: [])
            item.quantity += Int(quantity)
            if let index = item.allocations.firstIndex(where: { $0.id == order.id }) { item.allocations[index].quantity += Int(quantity) }
            else { item.allocations.append(.init(order: order, quantity: Int(quantity))) }
            items[key] = item
        }
        let sorted = items.values.sorted { ($0.shop.name, $0.sku, $0.title, $0.id) < ($1.shop.name, $1.sku, $1.title, $1.id) }
        return Self(orders: orders, items: sorted, excludedOrders: orders.count - eligible.count, excludedLines: excluded, loadedAt: now)
    }
    public static func csv(items: [PickingItem], checked: Set<String>, headings: [String]) -> Data {
        let rows = items.map { item in FederatedRecord(shop: item.shop, data: .object(["sku": .string(item.sku), "title": .string(item.title), "quantity": .number(Double(item.quantity)), "orders": .string(item.orderSummary), "checked": .bool(checked.contains(item.id))])) }
        let fields = ["shop", "sku", "title", "quantity", "orders", "checked"]
        return RecordCSV.encode(rows: rows, columns: zip(fields, headings).map { .init($0.0, $0.1) })
    }
    public static func pdf(items: [PickingItem], checked: Set<String>, title: String, subtitle: String, headings: [String]) throws -> Data {
        let bytes = NSMutableData(); var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(data: bytes), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        var y: CGFloat = 0, page = 0
        func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat = 10, width: CGFloat = 490) -> CGFloat {
            let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
            let attributed = NSAttributedString(string: value, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
            let setter = CTFramesetterCreateWithAttributedString(attributed)
            let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil, CGSize(width: width, height: 1000), nil)
            let height = ceil(fit.height) + 3
            let path = CGPath(rect: CGRect(x: x, y: y - height, width: width, height: height), transform: nil)
            CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil), context)
            return height
        }
        func begin() {
            if page > 0 { context.endPDFPage() }; context.beginPDFPage(nil); page += 1
            context.setFillColor(CGColor(gray: 0.1, alpha: 1)); context.setStrokeColor(CGColor(gray: 0.6, alpha: 1))
            _ = text(title, x: 42, y: 800, size: 22); _ = text(subtitle, x: 42, y: 764, size: 9)
            _ = text(String(page), x: 520, y: 35, size: 9, width: 35); y = 725
        }
        begin()
        for item in items {
            try Task.checkCancellation()
            if y < 180 { begin() }
            let label = String(item.title.prefix(300)) + (item.title.count > 300 ? "…" : "")
            context.stroke(CGRect(x: 43, y: y - 15, width: 11, height: 11))
            if checked.contains(item.id) { context.move(to: CGPoint(x: 45, y: y - 10)); context.addLine(to: CGPoint(x: 48, y: y - 13)); context.addLine(to: CGPoint(x: 53, y: y - 6)); context.strokePath() }
            y -= text(item.shop.name + " · " + (item.sku.isEmpty ? "—" : item.sku), x: 65, y: y, size: 9, width: 460)
            y -= text(label, x: 65, y: y, size: 12, width: 460)
            y -= text(headings[3] + ": " + String(item.quantity), x: 65, y: y, size: 10, width: 460)
            for allocation in item.allocations {
                try Task.checkCancellation()
                if y < 85 { begin(); y -= text(item.shop.name + " · " + item.sku, x: 65, y: y, size: 10, width: 460) }
                y -= text("#" + allocation.order.number + " × " + String(allocation.quantity), x: 65, y: y, size: 9, width: 460)
            }
            y -= 18; context.move(to: CGPoint(x: 42, y: y + 8)); context.addLine(to: CGPoint(x: 553, y: y + 8)); context.strokePath()
        }
        context.endPDFPage(); context.closePDF(); return bytes as Data
    }
}

extension ShopwareClient {
    public func pickingList(_ selections: [FederatedRecord]) async throws -> PickingList {
        let selected = Dictionary(grouping: selections, by: { $0.shop.id }).values.map { Array($0) }
        guard !selections.isEmpty, selections.count <= 200 else { throw ShopdeckError.message("Wähle zwischen einer und 200 Bestellungen.") }
        // At most four shops load at once. A failed or incomplete shop blocks the whole picking list.
        var orders: [PickingOrder] = [], lines: [(Shop, JSONValue)] = []
        try await withThrowingTaskGroup(of: ([PickingOrder], [(Shop, JSONValue)]).self) { group in
            func enqueue(_ index: Int) { let rows = selected[index]; group.addTask { try await self.pickingShop(rows) } }
            var next = min(4, selected.count); for index in 0..<next { enqueue(index) }
            for try await result in group { orders += result.0; lines += result.1; if next < selected.count { enqueue(next); next += 1 } }
        }
        try Task.checkCancellation(); return try PickingList.assemble(orders: orders, lines: lines)
    }
    private func pickingShop(_ selected: [FederatedRecord]) async throws -> ([PickingOrder], [(Shop, JSONValue)]) {
        let shop = selected[0].shop, ids = try Array(Set(selected.compactMap { $0.data["id"].string })).sorted().map(Validation.entityID)
        guard ids.count == selected.count else { throw ShopdeckError.message("Die Bestellauswahl enthält fehlende oder doppelte IDs.") }
        var orders: [PickingOrder] = [], lines: [(Shop, JSONValue)] = []
        if shop.isDemo {
            for id in ids {
                let row = try await detail(shop, entity: "order", id: id, resolveInheritance: false); orders.append(try .init(shop: shop, data: row))
                for (index, value) in row["lineItems"].array.enumerated() {
                    var line = value.object ?? [:]; line["orderId"] = .string(id)
                    // Demo IDs are stable within this order and use real API shaped line item fields.
                    line["id"] = .string(String(id.prefix(24)) + String(format: "%08x", Int(id.suffix(6), radix: 16)! * 16 + index))
                    lines.append((shop, .object(line)))
                }
            }
            return (orders, lines)
        }
        for offset in stride(from: 0, to: ids.count, by: 100) {
            let chunk = Array(ids.dropFirst(offset).prefix(100))
            let body: JSONValue = .object(["ids": .array(chunk.map(JSONValue.string)), "limit": .number(100), "associations": .object(["stateMachineState": .object([:])]), "includes": .object(["order": .array(["id", "orderNumber", "stateMachineState"].map(JSONValue.string)), "state_machine_state": .array(["technicalName"].map(JSONValue.string))])])
            let response = try await adminRequest(shop, request: .init(method: "POST", path: "search/order", body: body))
            let loaded = try response["data"].array.map { try PickingOrder(shop: shop, data: $0) }
            guard Set(loaded.map(\.orderID)) == Set(chunk) else { throw ShopdeckError.message(shop.name + ": Nicht alle ausgewählten Bestellungen konnten geladen werden.") }; orders += loaded
        }
        var total = 0
        for page in 1...100 {
            try Task.checkCancellation()
            let fields = ["id", "orderId", "type", "label", "quantity", "productId", "referencedId", "identifier", "payload", "good"]
            let body: JSONValue = .object(["page": .number(Double(page)), "limit": .number(100), "total-count-mode": .number(1), "filter": .array([.object(["type": .string("equalsAny"), "field": .string("orderId"), "value": .array(ids.map(JSONValue.string))])]), "sort": .array([.object(["field": .string("id"), "order": .string("ASC")])]), "includes": .object(["order_line_item": .array(fields.map(JSONValue.string))])])
            let response = try await adminRequest(shop, request: .init(method: "POST", path: "search/order-line-item", body: body))
            guard let count = response["total"].number, count >= 0 else { throw ShopdeckError.message("Die Gesamtzahl der Bestellpositionen fehlt.") }
            let rows = response["data"].array; total = Int(count); lines += rows.map { (shop, $0) }
            let lineIDs = try lines.map { try Validation.entityID($0.1["id"].string ?? "") }
            guard Set(lineIDs).count == lines.count else { throw ShopdeckError.message("Die Bestellpositionen haben sich während des Ladens verändert. Erneut laden.") }
            if lines.count == total { return (orders, lines) }
            if rows.isEmpty { break }
        }
        throw ShopdeckError.message(shop.name + ": Die Bestellpositionen konnten nicht vollständig geladen werden. Wähle weniger Bestellungen.")
    }
}
