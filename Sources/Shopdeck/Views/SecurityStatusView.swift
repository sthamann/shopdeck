import SwiftUI
import ShopdeckCore
struct SecurityStatusView:View {
    var model:AppModel
    var compact=false
    private var shops:[Shop]{model.scopedShops}
    private var warnings:[Shop]{shops.filter{shop in model.securityStatus[shop.id].map{[.missing,.inactive,.outdated].contains($0.state)} ?? false}}
    var body:some View {
        Group {if compact {if !warnings.isEmpty {HStack(spacing:10){Image(systemName:"exclamationmark.shield").foregroundStyle(.orange);Text(T("Security Plugin prüfen")+": "+warnings.map(\.name).joined(separator:", ")).font(.system(size:12,weight:.medium)).lineLimit(1);Spacer();Button(T("Details")){model.destination = .updates}}.padding(12).background(Color.orange.opacity(0.07),in:RoundedRectangle(cornerRadius:9))}}else{statusList}}.task{if model.securityStatus.isEmpty{await model.checkSecurityPlugins()}}
    }
    private var statusList:some View {
        VStack(alignment:.leading,spacing:14){if !compact{HStack{Text(T("Shopware Security Plugin")).font(.title3.bold());Spacer();Button(T("Sicherheit prüfen")){Task{await model.checkSecurityPlugins()}}.disabled(model.checkingSecurity)}}
            ForEach(shops){shop in if let status=model.securityStatus[shop.id],!compact || [.missing,.inactive,.outdated].contains(status.state){HStack(alignment:.top,spacing:12){Image(systemName:status.state == .current ? "checkmark.shield.fill":"exclamationmark.shield").foregroundStyle(status.state == .current ? Theme.blue:Color.orange);VStack(alignment:.leading,spacing:5){Text(shop.name+" · "+title(status.state)).font(.system(size:12,weight:.semibold));Text(detail(status)).font(.caption).foregroundStyle(.secondary);if shop.isDemo{Text(T("Demodaten")).font(.caption2).foregroundStyle(.secondary)}};Spacer();if compact{Button(T("Details")){model.destination = .updates}}else{Button(T("Administration öffnen")){model.openAdministration(shop)}}}.padding(14).background(Theme.surface,in:RoundedRectangle(cornerRadius:10))}}
            if !compact{Link(T("Offizielle Security Plugin Anleitung"),destination:URL(string:"https://developer.shopware.com/docs/guides/hosting/installation-updates/security-best-practices/security-plugin.html")!).font(.caption)}
        }.task{if model.securityStatus.isEmpty{await model.checkSecurityPlugins()}}
    }
    private func title(_ state:SecurityPluginStatus.State)->String {T(state == .current ? "Security Plugin aktuell":state == .missing ? "Security Plugin fehlt":state == .inactive ? "Security Plugin inaktiv":state == .outdated ? "Security Plugin Update verfügbar":"Security Status nicht bestätigt")}
    private func detail(_ status:SecurityPluginStatus)->String {if status.state == .unknown{return status.detail ?? T("Die aktuelle kompatible Version konnte nicht geprüft werden.")};if status.state == .missing{return T("Installiere und aktiviere SwagPlatformSecurity in diesem Shop.")};return T("Installiert")+": "+(status.installed ?? "–")+" · "+T("Aktuell kompatibel")+": "+(status.latest ?? "–")}
}
extension AppModel {
    func checkSecurityPlugins()async {guard !checkingSecurity else{return};checkingSecurity=true;defer{checkingSecurity=false};for shop in workspace.shops{do{securityStatus[shop.id]=try await client.securityPlugin(shop)}catch{securityStatus[shop.id] = .init(state:.unknown,detail:error.localizedDescription)}}}
}
