import Foundation

public struct AnalyticsOrder: Identifiable, Sendable {
    public var id: String { shopID.uuidString + (data["id"].string ?? "") }
    public let shopID: UUID
    public let shopName: String
    public let isDemo: Bool
    public let data: JSONValue
    public init(shop: Shop, data: JSONValue) { shopID = shop.id; shopName = shop.name; isDemo = shop.isDemo; self.data = data
        if let text=data["orderDateTime"].string {let formatter=ISO8601DateFormatter();formatter.formatOptions=[.withInternetDateTime,.withFractionalSeconds];date=formatter.date(from:text) ?? ISO8601DateFormatter().date(from:text)} else {date=nil}
    }
    public let date: Date?
    public var currency: String { data["currency"]["isoCode"].string ?? "?" }
    public var cancelled: Bool { data["stateMachineState"]["technicalName"].string == "cancelled" }
}
public struct AnalyticsSeriesPoint: Identifiable, Sendable { public var id: Date { date }; public let date: Date; public let revenue: Double; public let count: Int }
public struct CommerceAnalytics: Sendable {
    public var orders: [AnalyticsOrder] = []
    public var revenueMonths:[RevenueMonth] = []
    public var failures: [String] = []
    public var truncatedShops: [String] = []
    public var loadedAt: Date?
    public init() {}
    public var currencies: [String] { Array(Set(orders.map(\.currency)+revenueMonths.map(\.currency))).sorted() }
    public func period(days: Int, currency: String, now: Date = Date(), calendar: Calendar = .current) -> [AnalyticsOrder] {
        let since = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))!
        return orders.filter { $0.currency == currency && ($0.date ?? .distantPast) >= since && ($0.date ?? .distantFuture) <= now }
    }
    public func revenue(days: Int, currency: String, now: Date = Date()) -> Double { period(days: days, currency: currency, now: now).filter { !$0.cancelled }.reduce(0) { $0 + ($1.data["amountTotal"].number ?? 0) } }
    public func series(days: Int, currency: String, now: Date = Date(), calendar: Calendar = .current) -> [AnalyticsSeriesPoint] {
        (0..<days).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now))!
            let matching = orders.filter { $0.currency == currency && calendar.isDate($0.date ?? .distantPast, inSameDayAs: day) }
            return .init(date: day, revenue: matching.filter { !$0.cancelled }.reduce(0) { $0 + ($1.data["amountTotal"].number ?? 0) }, count: matching.count)
        }
    }
}
public enum DashboardWidget: String, Codable, CaseIterable, Identifiable, Sendable {
    case revenueMonth, revenueYear, monthlyRevenueChart, revenueToday, revenue7, revenue30, ordersToday, orders7, orders30, averageBasket, revenueChart, orderChart, shopRanking, recentOrders, openOrders, cancelledOrders, shippingRevenue, paymentStates, deliveryStates, products, customers, lowStock, connections
    public var id: String { rawValue }
    public var title: String { switch self {
    case .revenueMonth:return "Umsatz diesen Monat";case .revenueYear:return "Umsatz dieses Jahr";case .monthlyRevenueChart:return "Monatsumsätze";case .revenueToday: return "Umsatz heute"; case .revenue7: return "Umsatz · 7 Tage"; case .revenue30: return "Umsatz · 30 Tage"; case .ordersToday: return "Bestellungen heute"; case .orders7: return "Bestellungen · 7 Tage"; case .orders30: return "Bestellungen · 30 Tage"; case .averageBasket: return "Ø Warenkorb · 7 Tage"; case .revenueChart: return "Umsatzverlauf"; case .orderChart: return "Bestellungen im Verlauf"; case .shopRanking: return "Deine umsatzstärksten Shops"; case .recentOrders: return "Gerade eingegangen"; case .openOrders: return "Offene Bestellungen"; case .cancelledOrders: return "Stornierte Bestellungen"; case .shippingRevenue: return "Versanderlöse"; case .paymentStates: return "Zahlungsstatus"; case .deliveryStates: return "Lieferstatus"; case .products: return "Produkte insgesamt"; case .customers: return "Kunden insgesamt"; case .lowStock: return "Bestand im Blick"; case .connections: return "Verbundene Shops"
    } }
    public var icon: String { switch self { case .revenueMonth,.revenueYear,.monthlyRevenueChart,.revenueToday, .revenue7, .revenue30: return "eurosign.circle"; case .ordersToday, .orders7, .orders30: return "bag"; case .averageBasket: return "cart"; case .revenueChart: return "chart.xyaxis.line"; case .orderChart: return "chart.bar"; case .shopRanking: return "trophy"; case .recentOrders: return "clock"; case .openOrders: return "tray"; case .cancelledOrders: return "xmark.circle"; case .shippingRevenue, .deliveryStates: return "shippingbox"; case .paymentStates: return "creditcard"; case .products: return "cube.box"; case .customers: return "person.2"; case .lowStock: return "exclamationmark.circle"; case .connections: return "network" } }
}
public struct DashboardConfiguration: Codable, Equatable, Sendable {
    public var widgets: [DashboardWidget] = [.revenueToday, .ordersToday, .revenueMonth, .revenueYear, .monthlyRevenueChart, .revenue7, .revenueChart, .orderChart, .averageBasket, .shopRanking, .recentOrders, .openOrders, .orders7, .revenue30, .orders30, .paymentStates, .deliveryStates, .shippingRevenue, .cancelledOrders, .products, .customers, .lowStock, .connections]
    public var tiles:[DashboardTile]?
    public var effectiveTiles:[DashboardTile] {tiles ?? widgets.map{.init(id:$0.rawValue,widget:$0)}}
    public mutating func moveTile(_ id:String,before target:String){var list=effectiveTiles;guard id != target,let from=list.firstIndex(where:{$0.id==id})else{return};let value=list.remove(at:from);guard let to=list.firstIndex(where:{$0.id==target})else{return};list.insert(value,at:to);tiles=list}
    public init() {}
}
public struct DashboardTile:Codable,Identifiable,Equatable,Sendable {
    public var id:String
    public var widget:DashboardWidget
    public var shopIDs:Set<UUID>?
    public var channelKeys:Set<String>?
    public var currency:String?
    public var showShops:Bool = false
    public init(id:String=UUID().uuidString,widget:DashboardWidget){self.id=id;self.widget=widget}
}
extension ShopwareClient {
    public func analyticsOrders(_ shop: Shop, since: Date) async throws -> (orders: [JSONValue], complete: Bool) {
        let filter = RecordFilter(name: "Zeitraum", field: "orderDateTime", operation: "gte", value: ISO8601DateFormatter().string(from: since))
        var rows: [JSONValue] = []
        for page in 1...100 {
            try Task.checkCancellation()
            let result = try await search(shop, entity: "order", page: page, limit: 100, customFilters: [filter])
            rows += result.rows
            if rows.count >= result.total || result.rows.isEmpty { return (rows, rows.count >= result.total) }
        }
        return (rows, false)
    }
}
