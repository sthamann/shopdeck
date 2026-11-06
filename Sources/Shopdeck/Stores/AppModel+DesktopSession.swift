import Foundation
import ShopdeckCore

extension AppModel {
    func desktopTab(id: UUID) -> DesktopTab {
        var tab = DesktopTab(); tab.id = id; tab.destination = destination.rawValue; tab.shopID = selectedShopID; tab.shopIDs = listShopIDs
        tab.query = query; tab.filters = activeFilters; tab.sort = recordSort; tab.lowStock = lowStockOnly; tab.status = statusFilter; tab.page = page
        tab.channelKey = listChannelKey; tab.currency = listCurrency; tab.dashboardChannelKey = dashboardChannelKey; tab.dashboardCurrency = dashboardCurrency
        return tab
    }
    func restoreDesktopTab(_ tab: DesktopTab) {
        destination = Destination(rawValue: tab.destination) ?? .overview; selectedShopID = tab.shopID; listShopIDs = tab.shopIDs
        query = tab.query; activeFilters = tab.filters; recordSort = tab.sort; lowStockOnly = tab.lowStock; statusFilter = tab.status
        listChannelKey = tab.channelKey; listCurrency = tab.currency; dashboardChannelKey = tab.dashboardChannelKey; dashboardCurrency = tab.dashboardCurrency
        let size = UserDefaults.standard.integer(forKey: "pageSize"), cap = UserDefaults.standard.integer(forKey: "maxServerRecords")
        page = min(max(tab.page, 1), max(1, ((cap > 0 ? cap : 1000) + (size > 0 ? size : 50) - 1) / (size > 0 ? size : 50)))
        preservingRestoredPage = true; restoredQuery = tab.query
    }
}
