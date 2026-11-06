import Foundation
import ShopdeckCore

extension AppModel {
    func openAdministration(_ shop: Shop) { selectedShopID = shop.id; destination = .admin }
    func undoChange(_ record: ProductChangeRecord) async {
        guard let shop = workspace.shops.first(where: { $0.id == record.shopID }) else { error = T("Shop nicht gefunden"); return }
        isChangingProducts = true; defer { isChangingProducts = false }
        do {
            let result = try await changeService.undo(record.id, shop: shop)
            reload()
            if result?.status == .applied { notice = T("Änderung rückgängig gemacht."); await refresh() }
            else { error = T("Die Änderung muss im Änderungsverlauf geprüft werden.") }
        } catch { self.error = error.localizedDescription; reload() }
    }
    func undoBatch(_ origin:String)async {
        guard !isChangingProducts else{return};isChangingProducts=true;defer{isChangingProducts=false}
        let records=journal.changes.filter{$0.origin==origin && $0.status == .applied && $0.undoOfID==nil}.reversed()
        do{for record in records{guard let shop=workspace.shops.first(where:{$0.id==record.shopID})else{throw ShopdeckError.message(T("Shop entfernt"))};let result=try await changeService.undo(record.id,shop:shop);guard result?.status == .applied else{throw ShopdeckError.message(T("Die Änderung muss im Änderungsverlauf geprüft werden."))}};notice=T("Charge zurückgenommen.")}catch{self.error=error.localizedDescription}
        reload();await refresh()
    }
    func reconcileChange(_ record: ProductChangeRecord) async {
        guard let shop = workspace.shops.first(where: { $0.id == record.shopID }) else { error = T("Shop nicht gefunden"); return }
        isChangingProducts = true; defer { isChangingProducts = false }
        do {
            let result = try await changeService.reconcile(record.id, shop: shop)
            if result.origin.hasPrefix("ai"), [.applied, .failed].contains(result.status) {
                mutate { state in if let i = state.proposals.firstIndex(where: { $0.id == result.operationID }) { state.proposals[i].status = result.status == .applied ? "applied" : "pending" } }
            }
            reload(); notice = result.status == .uncertain ? T("Abweichende Werte. Bitte prüfe das Produkt.") : T("Aktueller Shopstand abgeglichen.")
        } catch { self.error = error.localizedDescription }
    }
}

extension AppModel {
    func openAdministration(_ record: ShopRecord) {
        openAdministration(record.shop)
        do { let session = try adminBrowsers.session(for: record.shop); var parts = URLComponents(url: session.home, resolvingAgainstBaseURL: false)!; parts.fragment = "/sw/\(record.entity)/detail/\(record.data["id"].string ?? "")/" + (record.entity == "order" ? "general" : "base"); if let url = parts.url { session.webView.load(URLRequest(url: url)) } } catch { self.error = error.localizedDescription }
    }
}
