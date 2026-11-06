import SwiftUI
import WebKit
import ShopdeckCore

private struct AdministrationWebView: NSViewRepresentable {
    let session: AdminBrowserSession
    func makeNSView(context: Context) -> WKWebView { session.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
struct AdministrationView: View {
    @Bindable var model: AppModel
    @LocalState<AdminBrowserSession?> private var session: AdminBrowserSession?
    @LocalState<String?> private var failure: String?
    var body: some View {
        VStack(spacing:0) {
            if model.selectedShopID != nil {HStack{Button{model.selectedShopID=nil}label:{Label(T("Zur Administrationsübersicht"),systemImage:"chevron.backward")}.buttonStyle(.borderless);Spacer()}.padding(.horizontal,20).padding(.vertical,10)}
        Group {
            if let shop = model.selectedShop {
                if shop.isDemo {
                    VStack(spacing: 22) {
                        ShopIcon(shop: shop, size: 64)
                        Text(T("Die echte Administration gehört zum echten Shop.")).font(.system(size: 25, weight: .bold)).multilineTextAlignment(.center)
                        Text(T("Dieses Demoprofil enthält fiktive Daten und keine Shopware Installation. Verbinde einen eigenen Shop oder starte einen lokalen Docker Testshop.")).font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 500)
                        Button(T("Shop verbinden")) { model.showingAddShop = true }.buttonStyle(.borderedProminent)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
                } else if let session {
                    browser(session, shop: shop)
                } else if let failure {
                    ContentUnavailableView(T("Administration konnte nicht geöffnet werden"), systemImage: "exclamationmark.triangle", description: Text(failure))
                } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            } else {
                ScrollView { VStack(alignment: .leading, spacing: 24) {
                    PageTitle(title: T("Deine Shopware Administration. Direkt hier."), subtitle: T("Wähle einen Shop. Jede Administration behält ihren eigenen Anmeldestatus."))
                    ForEach(model.workspace.shops) { shop in
                        Button { model.openAdministration(shop) } label: { HStack(spacing: 14) { ShopIcon(shop: shop, size: 40); VStack(alignment: .leading, spacing: 6) { Text(shop.name).font(.system(size: 17, weight: .semibold)); Text(shop.isDemo ? T("Demoprofil ohne echte Administration") : shop.host).font(.system(size: 12)).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.up.right") }.padding(.vertical, 15).contentShape(Rectangle()) }.buttonStyle(.plain)
                        Divider()
                    }
                }.padding(30) }
            }
        }}.task(id: model.selectedShop) {
            failure = nil; session = nil
            if let shop = model.selectedShop, !shop.isDemo { do { session = try model.adminBrowsers.session(for: shop) } catch { failure = error.localizedDescription } }
        }
    }
    private func browser(_ session: AdminBrowserSession, shop: Shop) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { session.webView.goBack() } label: { Image(systemName: "chevron.left") }.disabled(!session.canGoBack).help(T("Zurück"))
                Button { session.webView.goForward() } label: { Image(systemName: "chevron.right") }.disabled(!session.canGoForward).help(T("Weiter"))
                Button { session.reload() } label: { Image(systemName: "arrow.clockwise") }.help(T("Seite neu laden"))
                Button { session.goHome() } label: { Image(systemName: "house") }.help(T("Zur Administration"))
                Divider().frame(height: 18)
                Text(session.location.isEmpty ? session.home.absoluteString : session.location).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).textSelection(.enabled)
                Spacer()
                Button { session.openInBrowser() } label: { Label(T("Im Browser öffnen"), systemImage: "arrow.up.right.square") }
            }.buttonStyle(.borderless).padding(.horizontal, 20).frame(height: 45)
            if session.loading { ProgressView(value: session.progress).progressViewStyle(.linear).frame(height: 2) }
            if let error = session.error {
                HStack { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange); Text(error).font(.system(size: 12)); Spacer(); Button(T("Erneut laden")) { session.reload() } }.padding(15).background(Theme.surface)
            }
            if ShopLinks.isManagedLocal(shop) {
                HStack(spacing:14){Image(systemName:"key.fill").foregroundStyle(Theme.blue);VStack(alignment:.leading,spacing:4){Text(T("Standardzugang für deinen lokalen Testshop")).font(.system(size:12,weight:.semibold));Text(T("Benutzername")+": admin · "+T("Passwort")+": shopware").font(.system(size:12)).textSelection(.enabled)};Spacer();Button(T("Benutzername kopieren")){copyText("admin")};Button(T("Passwort kopieren")){copyText("shopware")};ShopStorefrontMenu(model:model,shop:shop)}.padding(14).background(Theme.blue.opacity(0.075))
            } else {HStack{Spacer();ShopStorefrontMenu(model:model,shop:shop)}.padding(.horizontal,16).padding(.vertical,8)}
            AdministrationWebView(session: session).id(session.id).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
