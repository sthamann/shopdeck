import WidgetKit
import SwiftUI
import AppIntents
import Charts

struct WidgetShop: AppEntity {
    static var typeDisplayRepresentation:TypeDisplayRepresentation = "Shop"
    static var defaultQuery=WidgetShopQuery()
    var id:String
    var name:String
    var displayRepresentation:DisplayRepresentation{.init(title:"\(name)")}
}
struct WidgetShopQuery:EntityQuery {
    func entities(for identifiers:[String]) async throws -> [WidgetShop] { CommerceWidgetSnapshot.read().scopes.filter{identifiers.contains($0.id)}.map{WidgetShop(id:$0.id,name:$0.name)} }
    func defaultResult() async -> WidgetShop? { .init(id:"all",name:String(localized:"Alle Shops")) }
    func suggestedEntities() async throws -> [WidgetShop] { CommerceWidgetSnapshot.read().scopes.map{WidgetShop(id:$0.id,name:$0.name)} }
}
enum WidgetMetric:String,AppEnum,CaseIterable {
    case revenueToday,revenue7,revenue30,revenueMonth,revenueYear,monthlyRevenueChart,ordersToday,orders7,orders30,averageBasket,revenueChart,orderChart,shopRanking,recentOrders,openOrders,cancelledOrders,shippingRevenue,paymentStates,deliveryStates,products,customers,lowStock,connections
    static var typeDisplayRepresentation:TypeDisplayRepresentation="Statistik"
    static var caseDisplayRepresentations:[Self:DisplayRepresentation] = [.revenueToday:"Umsatz heute",.revenue7:"Umsatz · 7 Tage",.revenue30:"Umsatz · 30 Tage",.revenueMonth:"Umsatz diesen Monat",.revenueYear:"Umsatz dieses Jahr",.monthlyRevenueChart:"Monatsumsätze",.ordersToday:"Bestellungen heute",.orders7:"Bestellungen · 7 Tage",.orders30:"Bestellungen · 30 Tage",.averageBasket:"Ø Warenkorb · 7 Tage",.revenueChart:"Umsatzverlauf",.orderChart:"Bestellungen im Verlauf",.shopRanking:"Deine umsatzstärksten Shops",.recentOrders:"Gerade eingegangen",.openOrders:"Offene Bestellungen",.cancelledOrders:"Stornierte Bestellungen",.shippingRevenue:"Versanderlöse",.paymentStates:"Zahlungsstatus",.deliveryStates:"Lieferstatus",.products:"Produkte insgesamt",.customers:"Kunden insgesamt",.lowStock:"Bestand im Blick",.connections:"Verbundene Shops"]
    var title:String {switch self {case .revenueToday:return "Umsatz heute";case .revenue7:return "Umsatz · 7 Tage";case .revenue30:return "Umsatz · 30 Tage";case .revenueMonth:return "Umsatz diesen Monat";case .revenueYear:return "Umsatz dieses Jahr";case .monthlyRevenueChart:return "Monatsumsätze";case .ordersToday:return "Bestellungen heute";case .orders7:return "Bestellungen · 7 Tage";case .orders30:return "Bestellungen · 30 Tage";case .averageBasket:return "Ø Warenkorb · 7 Tage";case .revenueChart:return "Umsatzverlauf";case .orderChart:return "Bestellungen im Verlauf";case .shopRanking:return "Deine umsatzstärksten Shops";case .recentOrders:return "Gerade eingegangen";case .openOrders:return "Offene Bestellungen";case .cancelledOrders:return "Stornierte Bestellungen";case .shippingRevenue:return "Versanderlöse";case .paymentStates:return "Zahlungsstatus";case .deliveryStates:return "Lieferstatus";case .products:return "Produkte insgesamt";case .customers:return "Kunden insgesamt";case .lowStock:return "Bestand im Blick";case .connections:return "Verbundene Shops";}}
}
struct CommerceConfiguration:WidgetConfigurationIntent {
    static var title:LocalizedStringResource="Shopdeck Statistik"
    static var description=IntentDescription("Wähle Shop, Kennzahl und Währung.")
    @Parameter(title:"Shop") var shop:WidgetShop?
    @Parameter(title:"Statistik") var metric:WidgetMetric?
    @Parameter(title:"Währung",default:"EUR") var currency:String
}
struct CommerceEntry:TimelineEntry {let date:Date;let configuration:CommerceConfiguration;let scope:CommerceWidgetScope?;var preset:WidgetMetric = .revenueToday;var metric:WidgetMetric{configuration.metric ?? preset}}
struct CommerceProvider:AppIntentTimelineProvider {
    var preset:WidgetMetric = .revenueToday
    func placeholder(in context:Context)->CommerceEntry{.init(date:Date(),configuration:.init(),scope:nil,preset:preset)}
    func snapshot(for configuration:CommerceConfiguration,in context:Context) async->CommerceEntry{entry(configuration)}
    func timeline(for configuration:CommerceConfiguration,in context:Context) async->Timeline<CommerceEntry>{.init(entries:[entry(configuration)],policy:.after(Date().addingTimeInterval(900)))}
    private func entry(_ configuration:CommerceConfiguration)->CommerceEntry{let scopes=CommerceWidgetSnapshot.read().scopes;return .init(date:Date(),configuration:configuration,scope:scopes.first{$0.id==(configuration.shop?.id ?? "all")},preset:preset)}
}
struct CommerceWidgetView:View {
    let entry:CommerceEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.locale) private var locale
    private let blue=Color(red:0,green:0.54,blue:1)
    private func widgetText(_ key:String)->String {let language=locale.language.languageCode?.identifier ?? "en";guard let path=Bundle.main.path(forResource:language,ofType:"lproj"),let bundle=Bundle(path:path)else{return key};return bundle.localizedString(forKey:key,value:key,table:nil)}
    private var currency:String{entry.configuration.currency.uppercased()}
    private var rows:[CommerceWidgetItem]{entry.scope?.highlights?[entry.metric.rawValue+"."+currency] ?? []}
    private var series:[CommerceWidgetDay]{entry.scope?.series[(["revenueYear","monthlyRevenueChart"].contains(entry.metric.rawValue) ? "monthly-":"")+currency] ?? []}
    private var hasChart:Bool{["revenueToday","revenue7","revenue30","revenueMonth","revenueYear","monthlyRevenueChart","revenueChart","ordersToday","orders7","orders30","orderChart"].contains(entry.metric.rawValue)}
    var body:some View {
        VStack(alignment:.leading,spacing:8){
            HStack{Image(systemName:entry.metric.rawValue.hasPrefix("orders") ? "bag.fill":"chart.bar.fill").foregroundStyle(blue);Text("shopdeck").font(.system(.caption,design:.rounded,weight:.bold));Spacer();if entry.scope?.isDemo==true{Text("Demo").font(.caption2).foregroundStyle(.orange)}}
            if family == .systemMedium {
                HStack(alignment:.center,spacing:18){metric.frame(maxWidth:.infinity,alignment:.leading);if !rows.isEmpty{breakdown(limit:3).frame(maxWidth:.infinity)}else if hasChart{chart.frame(maxWidth:.infinity,maxHeight:62)}}
            }else{metric;if family == .systemLarge{if !rows.isEmpty{breakdown(limit:5)}else if hasChart{chart.frame(maxHeight:145)}}}
            Spacer(minLength:0)
            if let scope=entry.scope{HStack{Text(scope.id == "all" ? widgetText("Alle Shops"):scope.name).lineLimit(1);Spacer();Text(scope.updatedAt,style:.time)}.font(.caption2).foregroundStyle(.secondary)}else{Text("Dashboard in Shopdeck öffnen, um Daten zu laden.").font(.caption2).foregroundStyle(.secondary)}
        }.containerBackground(for:.widget){Color(nsColor:.windowBackgroundColor)}.widgetURL(URL(string:"shopdeck://dashboard"))
    }
    private var metric:some View {VStack(alignment:.leading,spacing:6){Text(widgetText(entry.metric.title)).font(.caption).foregroundStyle(.secondary).lineLimit(2);Text(entry.scope?.metrics[currency]?[entry.metric.rawValue] ?? "–").font(.system(size:family == .systemSmall ? 25:32,weight:.bold,design:.rounded)).minimumScaleFactor(0.6).lineLimit(1).privacySensitive()}}
    private func breakdown(limit:Int)->some View {VStack(alignment:.leading,spacing:7){ForEach(Array(rows.prefix(limit).enumerated()),id:\.offset){_,row in HStack{Text(row.title).lineLimit(1);Spacer();Text(row.value).lineLimit(1)}.font(.caption2).privacySensitive()}}}
    private var chart:some View {Chart(Array(series.enumerated()),id:\.offset){_,point in BarMark(x:.value("Tag",point.date,unit:["revenueYear","monthlyRevenueChart"].contains(entry.metric.rawValue) ? .month:.day),y:.value("Wert",entry.metric.rawValue.hasPrefix("orders") || entry.metric == .orderChart ? Double(point.count):point.revenue)).foregroundStyle(blue).cornerRadius(3)}.chartXAxis(.hidden).chartYAxis(.hidden)}
}

struct ShopdeckCommerceWidget:Widget {
    var preset:WidgetMetric = .revenueToday
    var kind:String = "ShopdeckCommerce"
    var body:some WidgetConfiguration {AppIntentConfiguration(kind:kind,intent:CommerceConfiguration.self,provider:CommerceProvider(preset:preset)){entry in CommerceWidgetView(entry:entry)}.configurationDisplayName(LocalizedStringKey(preset.title)).description("23 Kennzahlen. Wähle Statistik, Shop oder Verkaufskanal und Währung über Widget bearbeiten.").supportedFamilies([.systemSmall,.systemMedium,.systemLarge])}
}
struct RevenueWidgets:WidgetBundle {var body:some Widget {ShopdeckCommerceWidget();ShopdeckCommerceWidget(preset:.revenueMonth,kind:"ShopdeckRevenueMonth");ShopdeckCommerceWidget(preset:.revenueYear,kind:"ShopdeckRevenueYear");ShopdeckCommerceWidget(preset:.monthlyRevenueChart,kind:"ShopdeckMonthlyChart")}}
struct OperationsWidgets:WidgetBundle {var body:some Widget {ShopdeckCommerceWidget(preset:.ordersToday,kind:"ShopdeckOrders");ShopdeckCommerceWidget(preset:.products,kind:"ShopdeckProducts");ShopdeckCommerceWidget(preset:.customers,kind:"ShopdeckCustomers");ShopdeckCommerceWidget(preset:.lowStock,kind:"ShopdeckStock");ShopdeckCommerceWidget(preset:.shopRanking,kind:"ShopdeckRanking");ShopdeckCommerceWidget(preset:.connections,kind:"ShopdeckConnections")}}
@main struct ShopdeckWidgets:WidgetBundle {var body:some Widget{RevenueWidgets().body;OperationsWidgets().body}}
