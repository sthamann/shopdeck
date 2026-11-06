import SwiftUI
import ShopdeckCore

extension Notification.Name { static let shopdeckAction = Notification.Name("ShopdeckAction") }
func appAction(_ action:String) { NotificationCenter.default.post(name:.shopdeckAction,object:action) }
struct MenuBarCommerceView:View {
    var model:AppModel
    @Environment(\.openWindow) private var openWindow
    var body:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack { Text("shopdeck").font(.system(size:20,weight:.bold,design:.rounded));Spacer();Text(model.dashboardCurrency).font(.caption).foregroundStyle(.secondary) }
            Text(T("Umsatz heute")).font(.caption).foregroundStyle(.secondary)
            Text(money(model.analytics.revenue(days:1,currency:model.dashboardCurrency),currency:model.dashboardCurrency)).font(.system(size:29,weight:.bold,design:.rounded)).monospacedDigit()
            Text("\(model.analytics.period(days:1,currency:model.dashboardCurrency).count) " + T("Bestellungen heute")).font(.callout)
            if let date=model.analytics.loadedAt { Text(T("Aktualisiert")+" "+localizedDate(date,date:.omitted,time:.shortened)).font(.caption).foregroundStyle(.secondary) } else { Text(T("Dashboard öffnen, um Daten zu laden.")).font(.caption).foregroundStyle(.secondary) }
            Divider()
            Button(T("Dashboard öffnen")) { appAction("dashboard");openWindow(id:"main");NSApp.activate(ignoringOtherApps:true) }
            Button(T("Schnellsuche")) { appAction("search");openWindow(id:"main");NSApp.activate(ignoringOtherApps:true) }
            Button(T("Aktualisieren")) { Task {await model.loadAnalytics()} }.disabled(model.loadingAnalytics)
        }.padding(22).frame(width:300)
    }
}
