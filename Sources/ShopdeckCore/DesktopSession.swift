import Foundation

public struct DesktopTab: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var destination = "overview"
    public var shopID: UUID?
    public var shopIDs: Set<UUID>?
    public var query = ""
    public var filters: [RecordFilter] = []
    public var sort: [RecordSort] = []
    public var lowStock = false
    public var status = "all"
    public var page = 1
    public var channelKey: String?
    public var currency: String?
    public var dashboardChannelKey: String?
    public var dashboardCurrency = "EUR"
    public init() {}
}
public struct DesktopSession: Codable, Equatable, Sendable {
    public var tabs: [DesktopTab] = []
    public var selected: UUID?
    public var secondary: UUID?
    public init(tabs: [DesktopTab] = [], selected: UUID? = nil, secondary: UUID? = nil) { self.tabs = tabs; self.selected = selected; self.secondary = secondary }
    public func validated(shopIDs validShops: Set<UUID>) -> Self {
        var result = self
        var seen = Set<UUID>()
        let destinations: Set<String> = ["overview", "admin", "frontends", "products", "orders", "customers", "followups", "changes", "history", "notifications", "updates", "ai", "activity"]
        result.tabs = tabs.filter { seen.insert($0.id).inserted }.map { tab in
            var copy = tab
            if !destinations.contains(copy.destination) { copy.destination = "overview" }
            if let id = copy.shopID, !validShops.contains(id) { copy.shopID = nil; copy.destination = "overview" }
            copy.shopIDs = copy.shopIDs.map { $0.intersection(validShops) }
            copy.query = String(copy.query.prefix(500)); copy.filters = Array(copy.filters.prefix(50)); copy.sort = Array(copy.sort.prefix(12)); copy.page = min(max(copy.page, 1), 10000)
            if let key = copy.channelKey, (try? CommerceChannelReference(key: key)).map({ !validShops.contains($0.shopID) }) != false { copy.channelKey = nil }
            if let key = copy.dashboardChannelKey, (try? CommerceChannelReference(key: key)).map({ !validShops.contains($0.shopID) }) != false { copy.dashboardChannelKey = nil }
            return copy
        }
        let ids = Set(result.tabs.map(\.id))
        if result.selected == nil || !ids.contains(result.selected!) { result.selected = result.tabs.first?.id }
        if result.secondary == result.selected || result.secondary.map({ !ids.contains($0) }) == true { result.secondary = nil }
        return result
    }
}
public struct DesktopPreset: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var name: String
    public var session: DesktopSession
    public init(name: String, session: DesktopSession) { self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)); self.session = session }
}
public struct DesktopState: Codable, Equatable, Sendable {
    public var lastSession = DesktopSession()
    public var presets: [DesktopPreset] = []
    public init() {}
}
extension WorkspaceStore {
    public func readDesktopState() throws -> DesktopState { try locked { try readLocalFile("desktop-session.json", fallback: DesktopState()) } }
    public func updateDesktopState(_ change: (inout DesktopState) throws -> Void) throws {
        try locked { var value = try readLocalFile("desktop-session.json", fallback: DesktopState()); try change(&value); try writeLocalFile(value, name: "desktop-session.json") }
    }
}
