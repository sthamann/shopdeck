import SwiftUI
import WebKit
import ShopdeckCore
private struct StorefrontBrowser:NSViewRepresentable {let session:AdminBrowserSession;func makeNSView(context:Context)->WKWebView{session.webView};func updateNSView(_ view:WKWebView,context:Context){}}
struct StorefrontsView:View {
    @Bindable var model:AppModel
    @LocalState<AdminBrowserSession?> private var session:AdminBrowserSession? = nil
    var body:some View {
        VStack(alignment:.leading,spacing:18){HStack{PageTitle(title:T("Deine Storefronts"),subtitle:T("Alle Domains, Verkaufskanäle, Sprachen und Währungen deiner Shops."));Spacer();if session != nil{Button(T("Alle Storefronts")){session=nil}};Button{Task{await model.loadSalesChannels(force:true)}}label:{Image(systemName:"arrow.clockwise")}}
            if let session {HStack{Button{session.webView.goBack()}label:{Image(systemName:"chevron.left")}.disabled(!session.canGoBack);Text(session.location).font(.caption).foregroundStyle(.secondary).lineLimit(1);Spacer();Button(T("Im Browser öffnen")){session.openInBrowser()};Button{session.reload()}label:{Image(systemName:"arrow.clockwise")}};StorefrontBrowser(session:session).id(session.id)}
            else {ScrollView{VStack(alignment:.leading,spacing:24){ForEach(model.scopedShops){shop in VStack(alignment:.leading,spacing:14){HStack{ShopIcon(shop:shop,size:32);Text(shop.name).font(.headline);if shop.isDemo{Text(T("Demodaten")).font(.caption).foregroundStyle(.secondary)};Spacer();Button(T("Administration öffnen")){model.openAdministration(shop)}}
                if let error=model.salesChannelErrors[shop.id]{Text(error).font(.caption).foregroundStyle(.secondary)}
                ForEach(model.salesChannels[shop.id] ?? []){channel in VStack(alignment:.leading,spacing:10){HStack{Text(channel.name).font(.system(size:13,weight:.semibold));Spacer();Text(channel.currencies.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)};ForEach(channel.domains){domain in HStack{Image(systemName:"globe").foregroundStyle(Theme.blue);VStack(alignment:.leading,spacing:4){Text(domain.url).font(.system(size:12,weight:.medium)).textSelection(.enabled);Text([domain.language,domain.currency].filter{!$0.isEmpty}.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)};Spacer();Button(T("Öffnen")){open(shop,domain:domain)}.disabled(shop.isDemo || domain.safeURL==nil);if let url=domain.safeURL{Link(T("Im Browser öffnen"),destination:url).disabled(shop.isDemo)}}};if channel.domains.isEmpty{Text(T("Dieser Verkaufskanal hat keine Storefront Domain.")).font(.caption).foregroundStyle(.secondary)}}.padding(16).background(Theme.surface,in:RoundedRectangle(cornerRadius:12))}
            };Divider()}}}}
        }.padding(26).task{await model.loadSalesChannels()}.onChange(of:model.selectedShopID){_,_ in session=nil}
    }
    private func open(_ shop:Shop,domain:StorefrontDomain){guard let url=domain.safeURL else{return};do{session=try AdminBrowserSession(shop:shop,url:url)}catch{model.error=error.localizedDescription}}
}
struct ShopStorefrontMenu:View {
    var model:AppModel;let shop:Shop
    var body:some View {Menu(T("Storefront öffnen")){ForEach(model.salesChannels[shop.id] ?? []){channel in ForEach(channel.domains){domain in if let url=domain.safeURL{Link(channel.name+" · "+domain.language+" · "+domain.currency,destination:url).disabled(shop.isDemo)}}};Button(T("Alle Storefronts")){model.selectedShopID=shop.id;model.destination = .frontends}}}
}
