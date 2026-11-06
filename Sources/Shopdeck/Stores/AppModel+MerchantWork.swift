import SwiftUI
import ShopdeckCore
import UserNotifications

struct MerchantFocusSnapshot {
    var key: String
    var counts: [MerchantFocus: Int] = [:]
    var failures: [MerchantFocus: [String]] = [:]
    var loadedAt: Date?
}

extension AppModel {
    var merchantFocusKey: String {
        [dashboardShops.map { $0.id.uuidString + $0.url }.sorted().joined(separator: ","), dashboardChannelKey ?? "all", dashboardCurrency,
         String(UserDefaults.standard.integer(forKey: "focusStockThreshold")), String(UserDefaults.standard.integer(forKey: "focusOverdueHours"))].joined(separator: "|")
    }
    var focusStockThreshold: Int { let value = UserDefaults.standard.integer(forKey: "focusStockThreshold"); return value > 0 ? value : 10 }
    var focusOverdueHours: Int { let value = UserDefaults.standard.integer(forKey: "focusOverdueHours"); return value > 0 ? value : 48 }
    func focusFilters(_ focus: MerchantFocus, now: Date = Date()) -> [RecordFilter] {
        focus.filters(stockThreshold: focusStockThreshold, overdueHours: focusOverdueHours, now: now).map { value in
            var copy = value
            let label = T(ListConfiguration.fields(focus.entity).first { $0.field == value.field }?.title ?? ["parentId": "Hauptprodukte", "coverId": "Produktbild", "description": "Beschreibung"][value.field] ?? value.field)
            let symbol = ["equals": "=", "lte": "≤", "gt": ">", "lt": "<", "isNull": T("fehlt"), "empty": T("leer")][value.operation] ?? value.operation
            copy.name = value.field == "parentId" && value.operation == "isNull" ? T("Hauptprodukte") : label + " " + symbol + (value.value.isEmpty ? "" : " " + T(value.value))
            return copy
        }
    }
    func openFocus(_ focus: MerchantFocus) {
        let channelKey = dashboardChannelKey, currency = dashboardCurrency, shopIDs = Set(dashboardShops.map(\.id))
        destination = focus.entity == "order" ? .orders : .products
        query = ""; lowStockOnly = false; statusFilter = "all"; page = 1
        listShopIDs = shopIDs; listChannelKey = channelKey; listCurrency = focus.entity == "order" ? currency : nil
        activeFilters = focusFilters(focus)
        Task { await loadRecords() }
    }
    func loadMerchantFocus(force: Bool = false) async {
        let key = merchantFocusKey
        if !force, focusSnapshot.key == key, let date = focusSnapshot.loadedAt, Date().timeIntervalSince(date) < 60 { return }
        if loadingFocus && focusLoadingKey == key && !force { return }
        focusLoadTask?.cancel()
        let generation = UUID(); focusGeneration = generation; focusLoadingKey = key; loadingFocus = true
        focusSnapshot = MerchantFocusSnapshot(key: key)
        let channel: CommerceChannelReference?
        do { channel = try CommerceChannelReference.resolve(dashboardChannelKey) }
        catch { loadingFocus = false; for focus in MerchantFocus.allCases { focusSnapshot.failures[focus] = [error.localizedDescription] }; return }
        let shops = dashboardShops.filter { channel == nil || channel!.shopID == $0.id }
        let currency = dashboardCurrency, now = Date(), threshold = focusStockThreshold, hours = focusOverdueHours
        let work = MerchantFocus.allCases.flatMap { focus in shops.map { (focus, $0) } }
        let task = Task { [client] in
            var result = MerchantFocusSnapshot(key: key)
            await withTaskGroup(of: (MerchantFocus, String, Int?, String?).self) { group in
                func enqueue(_ index: Int) {
                    let (focus, shop) = work[index]
                    group.addTask {
                        if Task.isCancelled { return (focus, shop.name, nil, nil) }
                        var filters = focus.filters(stockThreshold: threshold, overdueHours: hours, now: now)
                        if let channel { filters.append(.init(name: "Channel", field: focus.entity == "product" ? "visibilities.salesChannelId" : "salesChannelId", value: channel.id)) }
                        if focus.entity == "order" { filters.append(.init(name: "Currency", field: "currency.isoCode", value: currency)) }
                        do {
                            let response = try await client.search(shop, entity: focus.entity, limit: 1, customFilters: filters, compact: true)
                            return (focus, shop.name, response.total, nil)
                        } catch { return (focus, shop.name, nil, error.localizedDescription) }
                    }
                }
                var next = min(4, work.count)
                for index in 0..<next { enqueue(index) }
                for await (focus, shopName, count, error) in group {
                    if let count { result.counts[focus, default: 0] += count }
                    if let error { result.failures[focus, default: []].append(shopName + ": " + error) }
                    if next < work.count && !Task.isCancelled { enqueue(next); next += 1 }
                }
            }
            result.loadedAt = Date()
            return result
        }
        focusLoadTask = task
        let result = await task.value
        guard generation == focusGeneration else { return }
        loadingFocus = false; focusLoadTask = nil
        guard key == merchantFocusKey, !task.isCancelled else { return }
        focusSnapshot = result
    }
    var listShopSelectionTitle: String {
        if let ids = listShopIDs { return "\(ids.count) " + T("Shops ausgewählt") }
        return selectedShop?.name ?? T("Alle Shops")
    }
    func toggleListShop(_ id: UUID) {
        var ids = listShopIDs ?? Set(scopedShops.map(\.id))
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        selectedShopID = nil; listChannelKey = nil
        listShopIDs = ids.count == workspace.shops.count ? nil : ids
    }
    var followUps: [RecordFollowUp] { workbench.followUps ?? [] }
    var dueFollowUpCount: Int { followUps.filter { item in item.isDue(at: clock) && workspace.shops.contains(where: { $0.id == item.shopID }) }.count }
    func followUpDraft(_ record: ShopRecord) -> RecordFollowUp? {
        if let item = followUp(for: record) { return item }
        let title = record.entity == "order" ? "#" + (record.data["orderNumber"].string ?? record.data["id"].displayString) : record.entity == "customer" ? [record.data["firstName"].string, record.data["lastName"].string].compactMap { $0 }.joined(separator: " ") : record.data.at("name").string ?? record.data["id"].displayString
        return try? RecordFollowUp(shopID: record.shop.id, entity: record.entity, recordID: record.data["id"].string ?? "", title: title, reference: record.data["productNumber"].string ?? record.data["customerNumber"].string ?? record.data["orderNumber"].string ?? "")
    }
    func followUp(for record: ShopRecord) -> RecordFollowUp? {
        followUps.first { $0.shopID == record.shop.id && $0.entity == record.entity && $0.recordID == record.data["id"].string?.lowercased() }
    }
    @discardableResult func saveFollowUp(_ item: RecordFollowUp) -> Bool {
        do { try store.saveFollowUp(item); reload(); notice = T("Wiedervorlage gespeichert"); Task { await reconcileReminders() }; return true } catch { self.error = error.localizedDescription; return false }
    }
    func authorizeReminder(_ item: RecordFollowUp) async throws {
        guard item.reminderEnabled == true, item.completedAt == nil else { return }
        guard let date = item.dueAt, date > Date() else { throw ShopdeckError.message(T("Wähle einen zukünftigen Termin für die Mitteilung.")) }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else { throw ShopdeckError.message(T("Erlaube Shopdeck Mitteilungen in den macOS Systemeinstellungen.")) }
        } else if settings.authorizationStatus != .authorized && settings.authorizationStatus != .provisional { throw ShopdeckError.message(T("Erlaube Shopdeck Mitteilungen in den macOS Systemeinstellungen.")) }
    }
    func reconcileReminders() async {
        if let issue = await FollowUpNotifications.shared.synchronize(items: followUps, shops: workspace.shops) { reminderIssue = issue } else { reminderIssue = nil }
    }
    func completeFollowUp(_ item: RecordFollowUp, completed: Bool) {
        var next = item; next.completedAt = completed ? Date() : nil; saveFollowUp(next)
    }
    func postponeFollowUp(_ item: RecordFollowUp, days: Int) {
        var next = item; next.dueAt = Calendar.current.date(byAdding: .day, value: days, to: Date()); next.completedAt = nil; saveFollowUp(next)
    }
    func openFollowUp(_ item: RecordFollowUp) {
        guard let shop = workspace.shops.first(where: { $0.id == item.shopID }) else { error = T("Dieser Shop ist nicht mehr verbunden."); return }
        editingRecord = ShopRecord(shop: shop, data: .object(["id": .string(item.recordID)]), entity: item.entity)
    }
}
