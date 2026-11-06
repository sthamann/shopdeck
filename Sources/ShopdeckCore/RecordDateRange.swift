import Foundation

public enum RecordDateRange: String, Codable, CaseIterable, Identifiable, Sendable {
    case today, yesterday, last7, last30, thisMonth, lastMonth, thisYear
    public var id: String { rawValue }
    public var title: String {
        switch self { case .today: return "Heute"; case .yesterday: return "Gestern"; case .last7: return "Letzte 7 Tage"; case .last30: return "Letzte 30 Tage"; case .thisMonth: return "Dieser Monat"; case .lastMonth: return "Letzter Monat"; case .thisYear: return "Dieses Jahr" }
    }
    public func interval(now: Date = Date(), calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: now), tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        switch self {
        case .today: return DateInterval(start: today, end: tomorrow)
        case .yesterday: return DateInterval(start: calendar.date(byAdding: .day, value: -1, to: today)!, end: today)
        case .last7, .last30: return DateInterval(start: calendar.date(byAdding: .day, value: self == .last7 ? -6 : -29, to: today)!, end: tomorrow)
        case .thisMonth: return calendar.dateInterval(of: .month, for: now)!
        case .lastMonth: return calendar.dateInterval(of: .month, for: calendar.date(byAdding: .month, value: -1, to: now)!)!
        case .thisYear: return calendar.dateInterval(of: .year, for: now)!
        }
    }
    public func filter(field: String) -> RecordFilter { .init(name: title, field: field, operation: "dateRange", value: rawValue) }
    public static func field(for entity: String) -> String { entity == "order" ? "orderDateTime" : "createdAt" }
}

extension RecordFilter {
    /// Freeze one request's time window before federated pagination starts; saved views retain the relative expression.
    public func freezingDateRange(now: Date, calendar: Calendar = .current) throws -> [RecordFilter] {
        guard operation == "dateRange" else { return [self] }
        let value = try criteria(now: now, calendar: calendar)["parameters"]
        return [RecordFilter(name: name, field: field, operation: "gte", value: value["gte"].string!), RecordFilter(name: name, field: field, operation: "lt", value: value["lt"].string!)]
    }
}
