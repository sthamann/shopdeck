import Foundation
import ShopdeckCore

extension AppModel {
    func renameShop(_ id:UUID,name:String)throws {
        let clean=name.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clean.isEmpty,clean.count<=80 else{throw ShopdeckError.message(T("Der Shopname braucht 1 bis 80 Zeichen."))}
        try store.update{state in guard let index=state.shops.firstIndex(where:{$0.id==id})else{return};state.shops[index].name=clean}
        reload()
        if let shop=workspace.shops.first(where:{$0.id==id}) {records=records.map{$0.shop.id==id ? ShopRecord(shop:shop,data:$0.data,entity:$0.entity):$0};analytics.orders=analytics.orders.map{$0.shopID==id ? AnalyticsOrder(shop:shop,data:$0.data):$0}}
        notice=T("Shop umbenannt.")
    }
    @discardableResult func resolveAdminAPI(_ proposal:AdminAPIProposal,apply:Bool,refreshAfter:Bool=true,notify:Bool=true)async -> Bool {
        changeFailure=nil
        guard let shop=workspace.shops.first(where:{$0.id==proposal.shopID})else{changeFailure=T("Shop nicht gefunden");if notify{error=changeFailure};return false}
        do {
            try store.updateAdminAPIQueue{queue in guard let index=queue.proposals.firstIndex(where:{$0.id==proposal.id && $0.status=="pending"})else{throw ShopdeckError.message(T("Dieser Vorschlag wurde bereits bearbeitet."))};queue.proposals[index].status=apply ? "executing":"rejected"}
            reload();guard apply else{return true}
            do {let response=try await client.executeAdminApproval(shop,request:proposal.request);try store.updateAdminAPIQueue{queue in if let index=queue.proposals.firstIndex(where:{$0.id==proposal.id}){queue.proposals[index].status="applied";queue.proposals[index].completedAt=Date();queue.proposals[index].response=MCPDataProtection.scrub(response,personalData:shop.shareCustomerData)}};notice=T("API Aktion ausgeführt.")}
            catch {try store.updateAdminAPIQueue{queue in if let index=queue.proposals.firstIndex(where:{$0.id==proposal.id}){queue.proposals[index].status="uncertain";queue.proposals[index].error=error.localizedDescription}};changeFailure=error.localizedDescription;if notify{self.error=error.localizedDescription}}
            reload();if refreshAfter{await refresh()};return changeFailure==nil
        }catch{changeFailure=error.localizedDescription;if notify{self.error=error.localizedDescription};reload();return false}
    }
}
