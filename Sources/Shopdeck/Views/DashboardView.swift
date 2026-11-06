import SwiftUI
import Charts
import ShopdeckCore
import UniformTypeIdentifiers

struct DashboardView: View {
    @Bindable var model: AppModel
    var tile:DashboardTile? = nil
    @AppStorage("dashboardIncludeDemo") private var includeDemo = false
    @LocalState<Bool> private var configuring = false
    @LocalState<DashboardTile?> private var editingTile:DashboardTile? = nil
    private var configuration: DashboardConfiguration { model.dashboardConfiguration }
    private var widgetShops:[Shop]{model.dashboardUniverseShops.filter{tile?.shopIDs?.contains($0.id) ?? model.dashboardShops.contains($0)}}
    private var currency:String {tile?.currency ?? model.dashboardCurrency}
    private var analytics:CommerceAnalytics {model.analytics(for:tile)}
    private var series: [AnalyticsSeriesPoint] { analytics.series(days: 7, currency: currency) }
    private var week: [AnalyticsOrder] { analytics.period(days: 7, currency: currency) }
    private var month: [AnalyticsOrder] { analytics.period(days: 30, currency: currency) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) { Text(T("Alles im Blick. Dein Commerce.")).font(.system(size: 34, weight: .bold, design: .rounded)); Text(T("Ein Arbeitsplatz für alle Shops. Mit den Zahlen, die für dich zählen.")).font(.system(size: 13)).foregroundStyle(.secondary) }
                    Spacer()
                    Button { configuring = true } label: { Label(T("Dashboard anpassen"), systemImage: "slider.horizontal.3") }.controlSize(.large)
                }
                HStack(spacing: 18) {
                    HStack(spacing: 8) { Circle().fill(analytics.failures.isEmpty ? .green : .orange).frame(width: 7,height: 7); Text("\(model.dashboardShops.count) " + (model.dashboardShops.count == 1 ? T("Shop") : T("Shops"))); if model.dashboardShops.allSatisfy(\.isDemo) { Text(T("Demodaten")).foregroundStyle(.orange) } }.font(.system(size: 12, weight: .medium))
                    if model.loadingAnalytics { ProgressView().controlSize(.small); Text(T("Statistiken werden geladen …")).font(.caption).foregroundStyle(.secondary) }
                    else if let date = analytics.loadedAt { Text(T("Aktualisiert") + " " + localizedDate(date,date:.omitted,time:.shortened)).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if model.scopedShops.contains(where: \.isDemo) && model.scopedShops.contains(where:{!$0.isDemo}) { Toggle(T("Demoprofile einbeziehen"),isOn:$includeDemo).toggleStyle(.checkbox).font(.caption) }
                    Picker(T("Verkaufskanal"),selection:$model.dashboardChannelKey){Text(T("Alle Verkaufskanäle")).tag(nil as String?);ForEach(model.availableChannels.filter{channel in model.dashboardShops.contains{$0.id==channel.shopID}},id:\.key){channel in Text((model.workspace.shops.first{$0.id==channel.shopID}?.name ?? "")+" · "+channel.name).tag(Optional(channel.key))}}.frame(maxWidth:250)
                    Picker(T("Währung"), selection: $model.dashboardCurrency) { ForEach(Array(Set(analytics.currencies+[currency])).sorted(), id: \.self) { Text($0).tag($0) } }.frame(width: 130)
                }
                if !analytics.failures.isEmpty { Text(analytics.failures.joined(separator: "\n")).font(.caption).foregroundStyle(.orange) }
                if !analytics.truncatedShops.isEmpty { Text(T("Unvollständige Statistik: mehr als 10.000 Bestellungen in 30 Tagen.") + " " + analytics.truncatedShops.joined(separator: ", ")).font(.caption).foregroundStyle(.orange) }
                Text(T("Bestellumsatz inklusive Steuern, ohne stornierte Bestellungen. Keine Währungsumrechnung. Bestellungen und Umsatz nach gewählter Währung.")).font(.caption).foregroundStyle(.secondary)
                SecurityStatusView(model:model,compact:true)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 285), spacing: 18)], alignment: .leading, spacing: 18) {
                    ForEach(configuration.effectiveTiles) { item in
                        let widget=item.widget
                        DashboardView(model:model,tile:item).widgetView(widget).frame(maxWidth: .infinity, minHeight: item.showShops ? 315 : 205, maxHeight: item.showShops ? 315 : 205, alignment: .topLeading).padding(21)
                            .background(widget == .revenueToday ? Theme.blue.opacity(0.14) : Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(widget == .revenueToday ? Theme.blue.opacity(0.35) : Color.primary.opacity(0.07), lineWidth: 1))
                            .overlay(alignment:.topTrailing){Menu{Button(T("Widget konfigurieren")){editingTile=item};Button(T("Duplizieren")){var next=configuration;var copy=item;copy.id=UUID().uuidString;next.tiles=next.effectiveTiles+[copy];model.saveDashboard(next)};Button(T("Widget entfernen"),role:.destructive){model.removeDashboardTile(item.id)}}label:{Image(systemName:"ellipsis").padding(8)}.menuStyle(.borderlessButton).fixedSize().padding(6)}
                            .onDrag{NSItemProvider(object:("dashboard:"+item.id) as NSString)}
                            .onDrop(of:[UTType.text],isTargeted:nil){providers in guard let provider=providers.first else{return false};_ = provider.loadObject(ofClass:NSString.self){value,_ in guard let raw=value as? String,raw.hasPrefix("dashboard:")else{return};Task{@MainActor in model.moveDashboardTile(String(raw.dropFirst(10)),before:item.id)}};return true}
                            .contextMenu {Button(T("Widget konfigurieren")){editingTile=item};Button(T("Widget entfernen"),role:.destructive){model.removeDashboardTile(item.id)}}
                    }
                }
                if configuration.effectiveTiles.isEmpty { Button(T("Widgets auswählen")) { configuring = true }.buttonStyle(.borderedProminent).frame(maxWidth: .infinity).padding(60) }
            }.padding(26)
        }.task { if analytics.loadedAt == nil { await model.loadAnalytics() } }
        .onChange(of:includeDemo) {_,_ in Task{await model.loadAnalytics()}}
        .sheet(item:$editingTile){DashboardTileEditor(model:model,tile:$0)}
        .sheet(isPresented: $configuring) { DashboardConfigurationView(model: model) }
    }
    @ViewBuilder func widgetView(_ widget: DashboardWidget) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Image(systemName: widget.icon).font(.system(size: 15,weight: .medium)).foregroundStyle(Theme.blue); Text(T(widget.title)).font(.system(size: 13,weight: .semibold)); Spacer() }
            switch widget {
            case .revenueMonth:metric(money(analytics.calendarRevenue(.month,currency:currency),currency:currency),caption:T("Kalendermonat")+" · "+currency);revenueBars(height:55)
            case .revenueYear:metric(money(analytics.calendarRevenue(.year,currency:currency),currency:currency),caption:String(Calendar.current.component(.year,from:Date()))+" · "+currency);monthlyBars(height:65)
            case .monthlyRevenueChart:monthlyBars(height:145)
            case .revenueToday: metric(money(analytics.revenue(days: 1,currency: currency),currency: currency), caption: T("Heute") + " · " + currency); revenueBars(height: 74)
            case .revenue7: metric(money(analytics.revenue(days: 7,currency: currency),currency: currency), caption: T("Letzte 7 Kalendertage")); revenueBars(height: 74)
            case .revenue30: metric(money(analytics.revenue(days: 30,currency: currency),currency: currency), caption: T("Letzte 30 Kalendertage")); revenueBars(height: 74)
            case .ordersToday: metric(String(analytics.period(days: 1,currency: currency).count), caption: T("Heute eingegangen")); orderBars(height: 74)
            case .orders7: metric(String(week.count), caption: T("Letzte 7 Kalendertage")); orderBars(height: 74)
            case .orders30: metric(String(month.count), caption: T("Letzte 30 Kalendertage")); orderBars(height: 74)
            case .averageBasket: let completed = week.filter { !$0.cancelled }; metric(money(completed.isEmpty ? 0 : completed.reduce(0) { $0 + ($1.data["amountTotal"].number ?? 0) } / Double(completed.count), currency: currency),caption: T("Ohne stornierte Bestellungen")); Text("\(completed.count) " + T("Bestellungen")).font(.caption).foregroundStyle(.secondary)
            case .revenueChart: Chart(series) { point in AreaMark(x: .value(T("Tag"),point.date), y: .value(T("Umsatz"),point.revenue)).foregroundStyle(LinearGradient(colors:[Theme.blue.opacity(0.3),Theme.blue.opacity(0.02)],startPoint:.top,endPoint:.bottom)); LineMark(x:.value(T("Tag"),point.date),y:.value(T("Umsatz"),point.revenue)).foregroundStyle(Theme.blue).lineStyle(StrokeStyle(lineWidth: 2.5)) }.chartXAxis { AxisMarks(values:.stride(by:.day,count:2)) { AxisValueLabel(format:.dateTime.weekday(.abbreviated)) } }.chartYAxis { AxisMarks(position:.leading) }.frame(height:140)
            case .orderChart: orderBars(height: 140, axes: true)
            case .shopRanking: let ranking = Dictionary(grouping: week.filter { !$0.cancelled }, by: \.shopName).map { ($0.key,$0.value.reduce(0) { $0 + ($1.data["amountTotal"].number ?? 0) }) }.sorted { $0.1 > $1.1 }; ForEach(Array(ranking.prefix(4).enumerated()),id:\.offset) { i,item in HStack { Text("\(i+1)").foregroundStyle(.secondary); Text(item.0).lineLimit(1); Spacer(); Text(money(item.1,currency:currency)).fontWeight(.semibold) }.font(.system(size:12)) }; if ranking.isEmpty { empty() }
            case .recentOrders: ForEach(Array(month.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }.prefix(3))) { order in Button { if let shop = model.workspace.shops.first(where: { $0.id == order.shopID }) { model.editingRecord = ShopRecord(shop: shop,data:order.data,entity:"order") } } label: { HStack { VStack(alignment:.leading,spacing:4) { Text("#"+order.data["orderNumber"].localizedDisplayString).fontWeight(.medium); Text(order.shopName).foregroundStyle(.secondary) }; Spacer(); Text(money(order.data["amountTotal"].number ?? 0,currency:currency)) }.font(.system(size:12)) }.buttonStyle(.plain) }; if month.isEmpty { empty() }
            case .openOrders: metric(String(month.filter { $0.data["stateMachineState"]["technicalName"].string == "open" }.count),caption:T("Aus den letzten 30 Tagen")); drill(T("Bestellungen öffnen"), .orders)
            case .cancelledOrders: metric(String(month.filter(\.cancelled).count),caption:T("Aus den letzten 30 Tagen")); drill(T("Bestellungen öffnen"), .orders)
            case .shippingRevenue: metric(money(week.filter { !$0.cancelled }.reduce(0) { $0 + ($1.data["shippingTotal"].number ?? 0) },currency:currency),caption:T("Letzte 7 Kalendertage")); Image(systemName:"truck.box").font(.system(size:36,weight:.light)).foregroundStyle(Theme.blue.opacity(0.7))
            case .paymentStates: statusRows(association:"transactions")
            case .deliveryStates: statusRows(association:"deliveries")
            case .products: metric(snapshotTotal(\.products),caption:T("Alle ausgewählten Shops")); drill(T("Produkte öffnen"),.products)
            case .customers: metric(snapshotTotal(\.customers),caption:T("Alle ausgewählten Shops")); drill(T("Kunden öffnen"),.customers)
            case .lowStock: metric(snapshotTotal(\.lowStock),caption:T("Bestand ≤ 5")); Button(T("Produkte prüfen")) { model.destination = .products; model.activeFilters = [.init(name:T("Bestand ≤ 5"),field:"stock",operation:"lte",value:"5")]; Task { await model.loadRecords() } }.buttonStyle(.borderless)
            case .connections: metric("\(widgetShops.filter { model.connectionErrors[$0.id] == nil && model.snapshots[$0.id] != nil }.count) / \(widgetShops.count)",caption:T("Erfolgreich geladen")); ForEach(widgetShops.prefix(3)) { shop in HStack { Circle().fill(model.connectionErrors[shop.id] == nil ? .green : .orange).frame(width:6,height:6); Text(shop.name).lineLimit(1); Spacer(); Text(shop.isDemo ? T("Demo") : T("API")).foregroundStyle(.secondary) }.font(.caption) }
            }
            if tile?.showShops==true {
                Divider()
                ForEach(model.dashboardUniverseShops.filter{tile?.shopIDs?.contains($0.id) ?? model.dashboardShops.contains($0)}.prefix(4)){shop in
                    HStack {Text(shop.name).lineLimit(1);Spacer();Text(shopValue(widget,shop:shop))}.font(.system(size:11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength:0)
        }.accessibilityElement(children:.contain)
    }
    private func shopValue(_ widget:DashboardWidget,shop:Shop)->String {
        let scope=analytics.scoped(shopIDs:[shop.id])
        switch widget {
        case .products:return model.snapshots[shop.id].map{String($0.products)} ?? "–"
        case .customers:return model.snapshots[shop.id].map{String($0.customers)} ?? "–"
        case .lowStock:return model.snapshots[shop.id].map{String($0.lowStock)} ?? "–"
        case .connections:return model.connectionErrors[shop.id] == nil && model.snapshots[shop.id] != nil ? T("Verbunden"):T("Nicht verbunden")
        case .ordersToday:return String(scope.period(days:1,currency:currency).count)
        case .orders7:return String(scope.period(days:7,currency:currency).count)
        case .orders30,.recentOrders:return String(scope.period(days:30,currency:currency).count)
        case .orderChart:return String(scope.period(days:7,currency:currency).count)
        case .paymentStates:return String(scope.period(days:30,currency:currency).flatMap{$0.data["transactions"].array}.count)
        case .deliveryStates:return String(scope.period(days:30,currency:currency).flatMap{$0.data["deliveries"].array}.count)
        case .shippingRevenue:return money(scope.period(days:7,currency:currency).filter{!$0.cancelled}.reduce(0){$0+($1.data["shippingTotal"].number ?? 0)},currency:currency)
        case .averageBasket:let values=scope.period(days:7,currency:currency).filter{!$0.cancelled};return money(values.isEmpty ? 0:values.reduce(0){$0+($1.data["amountTotal"].number ?? 0)}/Double(values.count),currency:currency)
        case .openOrders:return String(scope.period(days:30,currency:currency).filter{$0.data["stateMachineState"]["technicalName"].string=="open"}.count)
        case .cancelledOrders:return String(scope.period(days:30,currency:currency).filter(\.cancelled).count)
        case .revenueMonth:return money(scope.calendarRevenue(.month,currency:currency),currency:currency)
        case .revenueYear,.monthlyRevenueChart:return money(scope.calendarRevenue(.year,currency:currency),currency:currency)
        default:return money(scope.revenue(days:widget == .revenueToday ? 1:widget == .revenue30 ? 30:7,currency:currency),currency:currency)
        }
    }
    private func monthlyBars(height:CGFloat)->some View {Chart(analytics.monthlySeries(currency:currency)){point in BarMark(x:.value(T("Monat"),point.date,unit:.month),y:.value(T("Umsatz"),point.revenue)).foregroundStyle(Theme.blue).cornerRadius(3)}.chartXAxis{AxisMarks(values:.stride(by:.month,count:2)){AxisValueLabel(format:.dateTime.month(.abbreviated))}}.chartYAxis(.hidden).frame(height:height)}
    private func metric(_ value: String, caption: String) -> some View { VStack(alignment:.leading,spacing:6) { Text(model.loadingAnalytics && analytics.loadedAt == nil ? "–" : value).font(.system(size:30,weight:.bold,design:.rounded)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6); Text(caption).font(.system(size:11)).foregroundStyle(.secondary) } }
    private func revenueBars(height: CGFloat) -> some View { Chart(series) { point in BarMark(x:.value("Date",point.date,unit:.day),y:.value("Revenue",point.revenue)).foregroundStyle(Theme.blue.opacity(0.85)).cornerRadius(3) }.chartXAxis(.hidden).chartYAxis(.hidden).frame(height:height) }
    private func orderBars(height: CGFloat, axes: Bool = false) -> some View { Chart(series) { point in BarMark(x:.value(T("Tag"),point.date,unit:.day),y:.value(T("Bestellungen"),point.count)).foregroundStyle(Theme.blue).cornerRadius(3) }.chartXAxis(axes ? .automatic : .hidden).chartYAxis(axes ? .automatic : .hidden).frame(height:height) }
    @ViewBuilder private func statusRows(association: String) -> some View { let entries = month.flatMap { $0.data[association].array }; let groups = Dictionary(grouping:entries) { $0["stateMachineState"]["technicalName"].string ?? "unknown" }.sorted { $0.value.count > $1.value.count }; ForEach(Array(groups.prefix(4)),id:\.key) { entry in HStack { Text(T(entry.key)); Spacer(); Text("\(entry.value.count)").fontWeight(.semibold) }.font(.system(size:12)); ProgressView(value:Double(entry.value.count),total:Double(max(entries.count,1))).tint(Theme.blue) }; if entries.isEmpty { empty() }; Text(T("Aus den letzten 30 Tagen")).font(.caption).foregroundStyle(.secondary) }
    private func empty() -> some View { Text(T("Noch keine Daten in diesem Zeitraum.")).font(.caption).foregroundStyle(.secondary).padding(.vertical,15) }
    private func drill(_ title: String,_ destination: Destination) -> some View { Button(title) { model.destination = destination }.buttonStyle(.borderless).font(.system(size:12,weight:.medium)) }
    private func snapshotTotal(_ key: KeyPath<ShopSnapshot,Int>) -> String { let shops=model.dashboardUniverseShops.filter{tile?.shopIDs?.contains($0.id) ?? model.dashboardShops.contains($0)};let loaded = shops.compactMap { model.snapshots[$0.id] }; guard loaded.count == shops.count else { return "–" }; return "\(loaded.reduce(0) { $0 + $1[keyPath:key] })" }
}
struct DashboardConfigurationView: View {
    var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LocalState<DashboardConfiguration> private var configuration: DashboardConfiguration
    @LocalState<String> private var search = ""
    @LocalState<String> private var category = "all"
    init(model: AppModel) { self.model=model; _configuration=LocalState(initialValue:model.dashboardConfiguration) }
    private var widgets:[DashboardWidget] { (Array(Set(configuration.effectiveTiles.map(\.widget))).sorted{a,b in configuration.effectiveTiles.firstIndex{$0.widget==a}! < configuration.effectiveTiles.firstIndex{$0.widget==b}!} + DashboardWidget.allCases.filter{widget in !configuration.effectiveTiles.contains{$0.widget==widget}}).filter { widget in (category=="all" || widget.category==category) && (search.isEmpty || T(widget.title).localizedCaseInsensitiveContains(search)) } }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack(alignment:.top) { VStack(alignment:.leading,spacing:7) { Text(T("Dein Dashboard zusammenstellen")).font(.system(size:26,weight:.bold,design:.rounded)); Text(T("Wähle mit einem Klick. Ziehe ausgewählte Widgets in die gewünschte Reihenfolge.")).font(.system(size:12)).foregroundStyle(.secondary) }; Spacer(); Text("\(configuration.effectiveTiles.count) / \(DashboardWidget.allCases.count)").font(.system(size:15,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(Theme.blue) }
            HStack(spacing:18) {
                HStack { Image(systemName:"magnifyingglass").foregroundStyle(.secondary);TextField(T("Widget suchen …"),text:$search).textFieldStyle(.plain) }.padding(10).background(Theme.surface,in:RoundedRectangle(cornerRadius:8)).frame(maxWidth:320)
                Picker(T("Bereich"),selection:$category) { Text(T("Alle Widgets")).tag("all");Text(T("Umsatz")).tag("revenue");Text(T("Bestellungen")).tag("orders");Text(T("Shops und Bestand")).tag("shops") }.pickerStyle(.segmented)
            }
            ScrollView {
                LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:16),count:3),spacing:16) {
                    ForEach(widgets) { widget in tile(widget) }
                }.padding(2)
                if widgets.isEmpty { ContentUnavailableView(T("Keine Treffer"),systemImage:"magnifyingglass").padding(35) }
            }
            HStack {
                Button(T("Abbrechen")){dismiss()}.keyboardShortcut(.cancelAction)
                Button(T("Alle Widgets")){configuration=DashboardConfiguration()}
                Spacer()
                Text(T("Die Vorschauen zeigen den aktuellen Datenstand deiner Shopauswahl.")).font(.caption).foregroundStyle(.secondary)
                Button(T("Speichern")){model.saveDashboard(configuration);dismiss()}.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width:1040,height:760)
    }
    private func toggle(_ widget:DashboardWidget){var items=configuration.effectiveTiles;if items.contains(where:{$0.widget==widget}){items.removeAll{$0.widget==widget}}else{items.append(.init(widget:widget))};configuration.tiles=items;configuration.widgets=items.map(\.widget)}
    private func tile(_ widget:DashboardWidget)->some View {
        let selected=configuration.effectiveTiles.contains{$0.widget==widget}
        return Button { toggle(widget) } label: {
            VStack(alignment:.leading,spacing:12) {
                HStack(alignment:.top,spacing:8) { Text(T(widget.title)).font(.system(size:13,weight:.semibold)).lineLimit(2).frame(maxWidth:.infinity,alignment:.leading);Image(systemName:selected ? "checkmark.circle.fill":"circle").font(.system(size:17)).foregroundStyle(selected ? Theme.blue:Color.secondary) }
                DashboardView(model:model).widgetView(widget).frame(width:390,height:215,alignment:.topLeading).padding(15).background(Theme.surface,in:RoundedRectangle(cornerRadius:12)).scaleEffect(0.69,anchor:.topLeading).frame(width:290,height:169,alignment:.topLeading).clipped().allowsHitTesting(false).accessibilityHidden(true)
            }.padding(13).frame(maxWidth:.infinity,alignment:.topLeading).background(selected ? Theme.blue.opacity(0.065):Color.primary.opacity(0.025),in:RoundedRectangle(cornerRadius:14)).overlay(RoundedRectangle(cornerRadius:14).strokeBorder(selected ? Theme.blue.opacity(0.7):Color.primary.opacity(0.12),lineWidth:selected ? 1.5:1))
        }.buttonStyle(.plain).accessibilityLabel(T(widget.title)).accessibilityValue(selected ? T("Ausgewählt"):T("Nicht ausgewählt"))
            .onDrag{NSItemProvider(object:widget.rawValue as NSString)}
            .onDrop(of:[UTType.text],isTargeted:nil){providers in
                guard let provider=providers.first else{return false}
                _ = provider.loadObject(ofClass:NSString.self){value,_ in guard let raw=value as? String,let source=DashboardWidget(rawValue:raw)else{return};Task{@MainActor in if let first=configuration.effectiveTiles.first(where:{$0.widget==source}),let target=configuration.effectiveTiles.first(where:{$0.widget==widget}){configuration.moveTile(first.id,before:target.id)}}};return true
            }
            .contextMenu {Button(selected ? T("Widget entfernen"):T("Widget hinzufügen")){toggle(widget)}}
            .animation(reduceMotion ? nil:.easeOut(duration:0.16),value:selected)
    }
}
extension DashboardWidget {
    var category:String { switch self {
    case .revenueMonth,.revenueYear,.monthlyRevenueChart,.revenueToday,.revenue7,.revenue30,.averageBasket,.revenueChart,.shippingRevenue:return "revenue"
    case .ordersToday,.orders7,.orders30,.orderChart,.recentOrders,.openOrders,.cancelledOrders,.paymentStates,.deliveryStates:return "orders"
    default:return "shops"
    } }
}
