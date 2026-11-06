import Foundation
import ShopdeckCore

extension AppModel {
    var currentSavedView: SavedView? {
        workbench.savedViews.first { $0.destination == destination.rawValue && $0.shopID == selectedShopID && $0.query == query && $0.lowStock == (lowStockOnly && destination == .products) && $0.status == statusFilter && ($0.filters ?? []) == activeFilters && $0.channelKey==listChannelKey && $0.currency==listCurrency && ($0.sort ?? RecordSort.defaults(destination.entity)) == (recordSort.isEmpty ? RecordSort.defaults(destination.entity):recordSort) }
    }
    func saveCurrentView(name: String) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 80, [.products, .orders, .customers].contains(destination) else { throw ShopdeckError.message(T("Gib der Ansicht einen Namen.")) }
        var preset = SavedView(name: clean, destination: destination.rawValue, shopID: selectedShopID, query: query, lowStock: lowStockOnly && destination == .products, status: statusFilter)
        preset.filters = activeFilters;preset.channelKey=listChannelKey;preset.currency=listCurrency;preset.sort=recordSort.isEmpty ? RecordSort.defaults(destination.entity):recordSort
        try store.updateWorkbench { state in
            if let i = state.savedViews.firstIndex(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame && $0.destination == preset.destination && $0.shopID == preset.shopID }) { var updated = preset; updated.id = state.savedViews[i].id; state.savedViews[i] = updated }
            else { state.savedViews.append(preset) }
        }
        reload(); notice = T("Ansicht gespeichert.")
    }
    func openSavedView(_ preset: SavedView) {
        guard let target = Destination(rawValue: preset.destination), [.products, .orders, .customers].contains(target) else { error = T("Diese Ansicht wird nicht unterstützt."); return }
        if let id = preset.shopID, !workspace.shops.contains(where: { $0.id == id }) { error = T("Der Shop dieser Ansicht wurde entfernt."); return }
        destination = target; selectedShopID = preset.shopID; query = preset.query; lowStockOnly = preset.lowStock; statusFilter = preset.status; activeFilters = preset.filters ?? [];listChannelKey=preset.channelKey;listCurrency=preset.currency;recordSort=preset.sort ?? RecordSort.defaults(target.entity); page = 1
        Task { await loadRecords() }
    }
    func removeSavedView(_ preset: SavedView) {
        do { try store.updateWorkbench { $0.savedViews.removeAll { $0.id == preset.id } }; reload() } catch { self.error = error.localizedDescription }
    }
    func searchRecords(_ target: Destination, term: String) {
        destination = target; query = term; page = 1
        Task { await loadRecords() }
    }
}

extension AppModel {
    var listConfiguration: ListConfiguration { workbench.lists?[destination.entity] ?? .standard(destination.entity) }
    func saveListConfiguration(_ configuration: ListConfiguration, entity: String) {
        do { try store.updateWorkbench { state in var lists = state.lists ?? [:]; lists[entity] = configuration; state.lists = lists }; reload() } catch { self.error = error.localizedDescription }
    }
}
