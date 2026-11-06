import Foundation

public enum DemoData {
    public static let shops: [Shop] = [
        Shop(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: "Nordlicht", url: "https://nordlicht.example", color: "blue", isDemo: true, mcpEnabled: true),
        Shop(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, name: "Studio Forma", url: "https://forma.example", color: "orange", isDemo: true, mcpEnabled: true),
        Shop(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, name: "Atelier Supply", url: "https://atelier.example", environment: "Staging", color: "mint", isDemo: true, mcpEnabled: true)
    ]
    private static let names = ["Everyday Backpack", "Ceramic Coffee Cup", "Linen Overshirt", "Desk Organizer", "Weekend Tote", "Merino Beanie", "Oak Desk Lamp", "Travel Bottle", "Canvas Pouch", "Wool Throw", "Studio Notebook", "Essential T Shirt"]
    private static let iso = ISO8601DateFormatter()
    public static func search(_ shop: Shop, entity: String, term: String, page: Int, limit: Int, lowStock: Bool, workspace: Workspace, status: String = "all", customFilters: [RecordFilter] = [],sort:[RecordSort]=[]) throws -> SearchResult {
        let index = shops.firstIndex(where: { $0.id == shop.id }) ?? 0
        var rows: [JSONValue] = []
        for i in 0..<24 {
            let id = String(format: "%032x", (index + 1) * 1000 + i + 1)
            var value: [String: JSONValue]
            switch entity {
            case "product":
                value = ["id": .string(id), "name": .string(names[i % names.count] + (i >= 12 ? " · Limited" : "")), "productNumber": .string("SW-\(index + 1)0\(String(format: "%03d", i + 1))"), "stock": .number(Double(i % 7 == 0 ? 2 : 18 + i * 3)), "active": .bool(i % 9 != 0), "description": .string("Designed for your everyday. Thoughtfully made with lasting materials."), "price": .array([.object(["gross": .number(Double(19 + i * 7) + 0.9), "net": .number(Double(19 + i * 7) / 1.19), "currencyId": .string("b7d2554b0ce847cd82f3ac9bd1c0dfca")])])]
                value.merge(workspace.demoOverrides["\(shop.id.uuidString):\(id)"] ?? [:]) { _, new in new }
            case "order":
                value = ["id": .string(id), "orderNumber": .string("\(10428 - i - index * 100)"), "amountTotal": .number(Double(49 + i * 17) + 0.9), "shippingTotal": .number(i % 3 == 0 ? 0 : 4.9), "orderDateTime": .string(iso.string(from: Date().addingTimeInterval(-Double(i * 3270 + index * 120)))), "stateMachineState": .object(["name": .string(i % 4 == 0 ? "Completed" : "Open"), "technicalName": .string(i % 4 == 0 ? "completed" : "open")]), "salesChannelId":.string(String(format:"%032x",(index+1)*100+i%2)),"salesChannel":.object(["name":.string(i%2==0 ? "Online Store":"International")]),"currency": .object(["isoCode": .string(i%4==3 ? "USD":"EUR")]), "orderCustomer": .object(["firstName": .string(["Emma", "Noah", "Mila", "Finn"][i % 4]), "lastName": .string("Example"), "email": .string("customer\(i + 1)@example.com")]), "lineItems": .array([.object(["label": .string(names[i % names.count]), "type": .string("product"), "good": .bool(true), "productId": .string(String(format: "%032x", (index + 1) * 1000 + i % 12 + 1)), "payload": .object(["productNumber": .string("SW-\(index + 1)0\(String(format: "%03d", i % 12 + 1))")]), "quantity": .number(Double(i % 3 + 1)), "totalPrice": .number(Double(49 + i * 17) + 0.9)])])]
            case "customer":
                value = ["id": .string(id), "firstName": .string(["Emma", "Noah", "Mila", "Finn", "Sophie", "Luca"][i % 6]), "lastName": .string("Example \(i + 1)"), "email": .string("customer\(i + 1)@example.com"), "customerNumber": .string("C-\(2000 + i)"), "active": .bool(true), "company": .string(i % 4 == 0 ? "Example Studio" : "")]
            default: value = ["id": .string(id), "name": .string("Storefront \(i + 1)")]
            }
            if entity=="product"{value["visibilities"] = .array((0...1).map{.object(["salesChannelId":.string(String(format:"%032x",(index+1)*100+$0))])})}
            if entity=="customer"{value["salesChannelId"] = .string(String(format:"%032x",(index+1)*100+i%2))}
            value["createdAt"] = .string(iso.string(from: Date().addingTimeInterval(-Double(i) * 86400)))
            value["updatedAt"] = .string(iso.string(from: Date().addingTimeInterval(-Double(i) * 3600)))
            rows.append(.object(value))
        }
        if !term.isEmpty { rows = rows.filter { $0.pretty.localizedCaseInsensitiveContains(term) } }
        if lowStock { rows = rows.filter { ($0["stock"].number ?? 999) <= 5 } }
        rows = rows.filter { SearchFilters.matches($0, entity: entity, status: status) }
        rows = rows.filter { row in customFilters.allSatisfy { $0.matches(row) } }
        if !sort.isEmpty{rows=RecordOrdering.indices(rows:rows,shops:rows.map{_ in shop.name},ids:rows.map{$0["id"].displayString},descriptors:sort.map{($0.field,$0.ascending)}).map{rows[$0]}}
        let total = rows.count
        return SearchResult(rows: Array(rows.dropFirst((page - 1) * limit).prefix(limit)), total: total)
    }
}

extension DemoData {
    public static func salesChannels(_ shop:Shop)->[CommerceSalesChannel] {
        let index=shops.firstIndex(where:{$0.id==shop.id}) ?? 0
        return (0..<2).map { i in
            let domain:JSONValue = .object(["id":.string("domain-\(i)"),"url":.string(shop.url+(i==0 ? "":"/en")),"currency":.object(["isoCode":.string(i==0 ? "EUR":"USD")]),"language":.object(["locale":.object(["code":.string(i==0 ? "de-DE":"en-GB")])])])
            let value:JSONValue = .object(["id":.string(String(format:"%032x",(index+1)*100+i)),"name":.string(i==0 ? "Online Store":"International"),"active":.bool(true),"type":.object(["name":.string("Storefront")]),"currencies":.array([.object(["isoCode":.string("EUR")]),.object(["isoCode":.string("USD")])]),"domains":.array([domain])])
            return CommerceSalesChannel(shopID:shop.id,data:value)
        }
    }
}
