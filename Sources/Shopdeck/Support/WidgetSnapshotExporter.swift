import Foundation
import AppKit
import WidgetKit
import ShopdeckCore

@MainActor enum WidgetSnapshotExporter {
    static func write(model:AppModel) {
        if UserDefaults.standard.bool(forKey:"dockOrderBadge") { NSApp.dockTile.badgeLabel="\(model.analytics.period(days:1,currency:model.dashboardCurrency).count)" } else { NSApp.dockTile.badgeLabel=nil }
        guard model.analytics.failures.isEmpty,model.analytics.truncatedShops.isEmpty,let date=model.analytics.loadedAt, let url=CommerceWidgetSnapshot.url else{return}
        var payload=CommerceWidgetSnapshot.read()
        let valid=Set(model.workspace.shops.map{$0.id.uuidString}+model.availableChannels.map{"channel:"+$0.key}+["all"])
        payload.scopes.removeAll{!valid.contains($0.id)}
        let shops=model.dashboardUniverseShops
        let groups:[(String,String,[Shop])] = [("all",T("Alle Shops"),shops)] + shops.map {($0.id.uuidString,$0.name,[$0])} + model.availableChannels.compactMap{channel in guard let shop=shops.first(where:{$0.id==channel.shopID})else{return nil};return ("channel:"+channel.key,shop.name+" · "+channel.name,[shop])}
        for (id,name,scoped) in groups {
            let ids=Set(scoped.map(\.id));let analytics=model.analytics.scoped(shopIDs:ids,channelKeys:id.hasPrefix("channel:") ? Set([String(id.dropFirst(8))]):nil)
            var metrics:[String:[String:String]]=[:],series:[String:[CommerceWidgetDay]]=[:],highlights:[String:[CommerceWidgetItem]]=[:]
            for currency in analytics.currencies.isEmpty ? ["EUR"] : analytics.currencies {
                let week=analytics.period(days:7,currency:currency),month=analytics.period(days:30,currency:currency),valid=week.filter{!$0.cancelled}
                func money(_ n:Double)->String{n.formatted(.currency(code:currency))}
                var values:[String:String]=[:]
                values["revenueMonth"]=money(analytics.calendarRevenue(.month,currency:currency))
                values["revenueYear"]=money(analytics.calendarRevenue(.year,currency:currency))
                for days in [1,7,30] { let revenueKey=days == 1 ? "revenueToday" : "revenue\(days)",orderKey=days == 1 ? "ordersToday" : "orders\(days)";values[revenueKey]=money(analytics.revenue(days:days,currency:currency));values[orderKey]="\(analytics.period(days:days,currency:currency).count)" }
                values["averageBasket"]=money(valid.isEmpty ? 0 : valid.reduce(0){$0+($1.data["amountTotal"].number ?? 0)}/Double(valid.count))
                values["openOrders"]="\(month.filter{$0.data["stateMachineState"]["technicalName"].string=="open"}.count)"
                values["cancelledOrders"]="\(month.filter(\.cancelled).count)"
                values["shippingRevenue"]=money(valid.reduce(0){$0+($1.data["shippingTotal"].number ?? 0)})
                let snapshots=scoped.compactMap{model.snapshots[$0.id]}
                values["products"]=snapshots.count==scoped.count ? "\(snapshots.reduce(0){$0+$1.products})" : "–"
                values["customers"]=snapshots.count==scoped.count ? "\(snapshots.reduce(0){$0+$1.customers})" : "–"
                values["lowStock"]=snapshots.count==scoped.count ? "\(snapshots.reduce(0){$0+$1.lowStock})" : "–"
                values["revenueChart"]=values["revenue7"];values["monthlyRevenueChart"]=values["revenueYear"];values["orderChart"]=values["orders7"]
                values["connections"]="\(scoped.filter{model.connectionErrors[$0.id]==nil && model.snapshots[$0.id] != nil}.count) / \(scoped.count)"
                let ranking=Dictionary(grouping:valid,by:\.shopName).map{($0.key,$0.value.reduce(0){$0+($1.data["amountTotal"].number ?? 0)})}.sorted{$0.1>$1.1}.map{CommerceWidgetItem(title:$0.0,value:money($0.1))}
                values["shopRanking"]=values["revenue7"];highlights["shopRanking."+currency]=ranking
                values["recentOrders"]="\(month.count)";highlights["recentOrders."+currency]=month.sorted{($0.date ?? .distantPast)>($1.date ?? .distantPast)}.prefix(4).map{.init(title:"#"+$0.data["orderNumber"].localizedDisplayString,value:money($0.data["amountTotal"].number ?? 0))}
                for (key,association) in [("paymentStates","transactions"),("deliveryStates","deliveries")] {
                    let records=month.flatMap{$0.data[association].array},groups=Dictionary(grouping:records){$0["stateMachineState"]["technicalName"].string ?? "unknown"}
                    values[key]="\(records.count)";highlights[key+"."+currency]=groups.sorted{$0.value.count>$1.value.count}.map{.init(title:T($0.key),value:String($0.value.count))}
                }
                if id.hasPrefix("channel:") {for key in ["products","customers","lowStock"]{values[key]="–"}}
                series["monthly-"+currency]=analytics.monthlySeries(currency:currency).map{.init(date:$0.date,revenue:$0.revenue,count:$0.count)}
                metrics[currency]=values;series[currency]=analytics.series(days:7,currency:currency).map{.init(date:$0.date,revenue:$0.revenue,count:$0.count)}
            }
            payload.scopes.removeAll{$0.id==id};payload.scopes.append(.init(id:id,name:name,isDemo:scoped.allSatisfy(\.isDemo),updatedAt:date,metrics:metrics,series:series,highlights:highlights))
        }
        do {try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try JSONEncoder().encode(payload).write(to:url,options:.atomic);WidgetCenter.shared.reloadAllTimelines()} catch { model.notice=T("Desktop Widgets konnten nicht aktualisiert werden.")+" "+error.localizedDescription }
        if UserDefaults.standard.bool(forKey:"dockOrderBadge") { NSApp.dockTile.badgeLabel="\(model.analytics.period(days:1,currency:model.dashboardCurrency).count)" } else { NSApp.dockTile.badgeLabel=nil }
    }
}
