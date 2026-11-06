import Foundation
import ShopdeckCore
extension AppModel {
    @discardableResult func resolveOperation(_ operation:AutomationOperation,apply:Bool,refreshAfter:Bool=true)async->Bool {
        changeFailure=nil
        guard let shop=workspace.shops.first(where:{$0.id==operation.shopID})else{changeFailure=T("Shop entfernt");return false}
        do {
            if apply{_ = try await AutomationService(store:store,client:client).execute(operation.id,shop:shop);notice=T("Vorgang ausgeführt und geprüft.")}
            else{try store.updateAutomationQueue{queue in guard let index=queue.operations.firstIndex(where:{$0.id==operation.id && $0.status=="pending"})else{throw ShopdeckError.message(T("Dieser Vorschlag wurde bereits bearbeitet."))};queue.operations[index].status="rejected";queue.operations[index].completedAt=Date()}}
            reload();if refreshAfter{await refresh()};return true
        }catch{changeFailure=error.localizedDescription;self.error=error.localizedDescription;reload();return false}
    }
}
