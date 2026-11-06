import Foundation
import ShopdeckCore

extension AppModel {
    var dashboardUniverseShops:[Shop] {let shops=workspace.shops;return !UserDefaults.standard.bool(forKey:"dashboardIncludeDemo") && shops.contains(where:{!$0.isDemo}) ? shops.filter{!$0.isDemo}:shops}
    var dashboardShops:[Shop] {dashboardUniverseShops.filter{selectedShopID==nil || $0.id==selectedShopID}}
    var dashboardConfiguration:DashboardConfiguration {workbench.dashboard ?? DashboardConfiguration()}
    var availableChannels:[CommerceSalesChannel] {workspace.shops.flatMap{salesChannels[$0.id] ?? []}}
    func saveDashboard(_ configuration:DashboardConfiguration){do{try store.updateWorkbench{$0.dashboard=configuration};reload()}catch{self.error=error.localizedDescription}}
    func removeDashboardTile(_ id:String){var next=dashboardConfiguration;next.tiles=next.effectiveTiles.filter{$0.id != id};saveDashboard(next)}
    func moveDashboardTile(_ id:String,before target:String){var next=dashboardConfiguration;next.moveTile(id,before:target);saveDashboard(next)}
    func loadSalesChannels(force:Bool=false)async {
        for shop in workspace.shops {if !force,let loaded=channelLoadedAt[shop.id],Date().timeIntervalSince(loaded)<300{continue};do{salesChannels[shop.id]=try await client.salesChannels(shop);salesChannelErrors[shop.id]=nil;channelLoadedAt[shop.id]=Date()}catch{salesChannelErrors[shop.id]=error.localizedDescription}}
    }
    func analytics(for tile:DashboardTile?)->CommerceAnalytics {let ids=tile?.shopIDs ?? Set(dashboardShops.map(\.id));let keys=tile?.channelKeys ?? dashboardChannelKey.map{Set([$0])};return analytics.scoped(shopIDs:ids,channelKeys:keys)}
    func loadAnalytics()async {
        guard !loadingAnalytics else{return};loadingAnalytics=true;defer{loadingAnalytics=false}
        let shops=dashboardUniverseShops,since=Calendar.current.date(byAdding:.day,value:-29,to:Calendar.current.startOfDay(for:Date()))!
        var result=CommerceAnalytics()
        await withTaskGroup(of:(Shop,[JSONValue],[RevenueMonth],Bool,String?).self){group in
            for shop in shops {group.addTask{[client] in do{async let orders=client.analyticsOrders(shop,since:since);async let months=client.revenueMonths(shop);let (data,totals)=try await (orders,months);return (shop,data.orders,totals,data.complete,nil)}catch{return (shop,[],[],false,error.localizedDescription)}}}
            for await (shop,rows,months,complete,error) in group {result.orders += rows.map{AnalyticsOrder(shop:shop,data:$0)};result.revenueMonths += months;if let error{result.failures.append(shop.name+": "+error)}else if !complete{result.truncatedShops.append(shop.name)}}
        }
        guard shops.map(\.id)==dashboardUniverseShops.map(\.id)else{loadingAnalytics=false;await loadAnalytics();return}
        result.loadedAt=Date();analytics=result
        if !result.currencies.contains(dashboardCurrency),let first=result.currencies.first{dashboardCurrency=first}
        await loadSalesChannels();WidgetSnapshotExporter.write(model:self)
    }
}
