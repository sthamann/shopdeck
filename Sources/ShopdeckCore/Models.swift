import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> JSONValue { object?[key] ?? .null }
    public var object: [String: JSONValue]? { if case .object(let v) = self { return v }; return nil }
    public var array: [JSONValue] { if case .array(let v) = self { return v }; return [] }
    public var string: String? { if case .string(let v) = self { return v }; return nil }
    public var number: Double? { if case .number(let v) = self { return v }; return nil }
    public var bool: Bool? { if case .bool(let v) = self { return v }; return nil }
    public var pretty: String { String(data: (try? JSONEncoder.pretty.encode(self)) ?? Data(), encoding: .utf8) ?? "{}" }
    public static func from(_ value: Any) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]))
    }
}
extension JSONEncoder {
    public static var pretty: JSONEncoder { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; return e }
}

public struct Shop: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var url: String
    public var environment: String
    public var color: String
    public var isDemo: Bool
    public var mcpEnabled: Bool
    public var shareCustomerData: Bool
    public var containerName: String?
    public var groupID: UUID?
    public var faviconFile: String?
    public init(id: UUID = UUID(), name: String, url: String, environment: String = "Produktion", color: String = "blue", isDemo: Bool = false, mcpEnabled: Bool = false, shareCustomerData: Bool = false) {
        self.id = id; self.name = name; self.url = url; self.environment = environment; self.color = color; self.isDemo = isDemo; self.mcpEnabled = mcpEnabled; self.shareCustomerData = shareCustomerData
    }
    public var host: String { URL(string: url)?.host ?? url }
    public var initials: String { String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased() }
}
public struct Credentials: Codable, Sendable {
    public var clientID: String
    public var clientSecret: String
    public init(clientID: String, clientSecret: String) { self.clientID = clientID; self.clientSecret = clientSecret }
}
public struct ChangeProposal: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var shopID: UUID
    public var productID: String
    public var productName: String
    public var changes: [String: JSONValue]
    public var expectedBefore:[String:JSONValue]?
    public var reason: String
    public var createdAt: Date = Date()
    public var status: String = "pending"
    public var resolvedAt: Date?
    public init(shopID: UUID, productID: String, productName: String, changes: [String: JSONValue], reason: String) {
        self.shopID = shopID; self.productID = productID; self.productName = productName; self.changes = changes; self.reason = reason
    }
}
public struct Activity: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var date: Date = Date()
    public var shopID: UUID?
    public var title: String
    public var detail: String
    public init(shopID: UUID? = nil, title: String, detail: String) { self.shopID = shopID; self.title = title; self.detail = detail }
}
public struct Workspace: Codable, Sendable {
    public var shops: [Shop] = []
    public var proposals: [ChangeProposal] = []
    public var activities: [Activity] = []
    public var demoOverrides: [String: [String: JSONValue]] = [:]
    public var rules: [OrderRule] = []
    public var orderCursors: [String: OrderCursor] = [:]
    public var groups: [ShopGroup] = []
    public init() {}
}
public struct ShopGroup: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public init(name: String) { self.name = name }
}
public struct SearchResult: Sendable {
    public var rows: [JSONValue]
    public var total: Int
    public init(rows: [JSONValue], total: Int) { self.rows = rows; self.total = total }
}
public struct ShopSnapshot: Sendable {
    public var shop: Shop
    public var products: Int
    public var orders: Int
    public var customers: Int
    public var lowStock: Int
    public var recentOrders: [JSONValue]
    public var updatedAt: Date = Date()
}
public enum ShopdeckError: LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}

public enum Validation {
    public static func productRestoration(_ input: [String: JSONValue]) throws -> [String: JSONValue] {
        guard !input.isEmpty, Set(input.keys).isSubset(of: ["name", "description", "stock", "active"]) else { throw ShopdeckError.message("Ungültige Wiederherstellungsdaten.") }
        let regular = input.filter { $0.value != .null }
        if !regular.isEmpty { _ = try productChanges(regular) }
        for (key, value) in input where value == .null { guard ["name", "description", "active"].contains(key) else { throw ShopdeckError.message("Dieser Wert kann nicht als Vererbung wiederhergestellt werden.") } }
        return input
    }
    public static func shopURL(_ input: String) throws -> URL {
        let raw = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: raw), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else {
            throw ShopdeckError.message("Gib eine gültige HTTPS Shopadresse ein. Für lokale Shops ist HTTP auf localhost erlaubt.")
        }
        return url
    }
    public static func entityID(_ value: String) throws -> String {
        let clean = value.replacingOccurrences(of: "-", with: "").lowercased()
        guard clean.count == 32, clean.allSatisfy({ $0.isHexDigit }) else { throw ShopdeckError.message("Die Shopware ID muss aus 32 hexadezimalen Zeichen bestehen.") }
        return clean
    }
    public static func productChanges(_ input: [String: JSONValue]) throws -> [String: JSONValue] {
        guard !input.isEmpty, Set(input.keys).isSubset(of: ["name", "description", "stock", "active"]) else {
            throw ShopdeckError.message("Erlaubt sind Name, Beschreibung, Bestand und Aktivstatus.")
        }
        for (key, value) in input {
            switch key {
            case "stock": guard let n = value.number, n.isFinite, n >= 0, n <= 2147483647, n.rounded() == n else { throw ShopdeckError.message("Der Bestand muss eine ganze Zahl ab 0 sein.") }
            case "active": guard value.bool != nil else { throw ShopdeckError.message("Der Aktivstatus muss true oder false sein.") }
            case "name": guard let s = value.string, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, s.count <= 255 else { throw ShopdeckError.message("Der Produktname muss 1 bis 255 Zeichen enthalten.") }
            case "description": guard let s = value.string, s.count <= 100_000 else { throw ShopdeckError.message("Die Beschreibung ist zu lang oder kein Text.") }
            default: break
            }
        }
        return input
    }
}
