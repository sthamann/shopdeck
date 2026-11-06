import Foundation

public struct OrderCondition: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID = UUID()
    public var field: String
    public var comparison: String
    public var value: String
    public init(field: String = "amountTotal", comparison: String = "gte", value: String = "100") { self.field = field; self.comparison = comparison; self.value = value }
    public func matches(_ order: JSONValue) -> Bool {
        let actual = field.split(separator: ".").reduce(order) { $0[String($1)] }
        switch comparison {
        case "gte": guard let n = actual.number, let target = Double(value.replacingOccurrences(of: ",", with: ".")) else { return false }; return n >= target
        case "lte": guard let n = actual.number, let target = Double(value.replacingOccurrences(of: ",", with: ".")) else { return false }; return n <= target
        case "contains": return actual.string?.localizedCaseInsensitiveContains(value) ?? false
        default:
            if let number = actual.number, let target = Double(value.replacingOccurrences(of: ",", with: ".")) { return number == target }
            return actual.string?.caseInsensitiveCompare(value) == .orderedSame
        }
    }
}
public struct OrderRule: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var shopID: UUID?
    public var enabled: Bool = true
    public var matchAll: Bool = true
    public var conditions: [OrderCondition] = []
    public init(name: String, shopID: UUID? = nil, conditions: [OrderCondition] = [], matchAll: Bool = true) { self.name = name; self.shopID = shopID; self.conditions = conditions; self.matchAll = matchAll }
    public func matches(_ order: JSONValue, shopID: UUID) -> Bool {
        guard enabled, self.shopID == nil || self.shopID == shopID else { return false }
        if conditions.isEmpty { return true }
        return matchAll ? conditions.allSatisfy { $0.matches(order) } : conditions.contains { $0.matches(order) }
    }
}
public struct OrderCursor: Codable, Sendable {
    public var seenIDs: [String]
    public var lastChecked: Date
    public init(seenIDs: [String], lastChecked: Date = Date()) { self.seenIDs = seenIDs; self.lastChecked = lastChecked }
}
public enum VersionComparison {
    public static func isNewer(_ candidate: String, than installed: String) -> Bool {
        func parts(_ s: String) -> [Int]? {
            let clean = s.hasPrefix("v") ? String(s.dropFirst()) : s
            let chunks = clean.split(separator: ".")
            guard chunks.count >= 3, chunks.allSatisfy({ Int($0) != nil }) else { return nil }
            return chunks.compactMap { Int($0) }
        }
        guard let a = parts(candidate), let b = parts(installed) else { return false }
        for i in 0..<max(a.count, b.count) { let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0; if x != y { return x > y } }
        return false
    }
}
