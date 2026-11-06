import SwiftUI
import ShopdeckCore
struct OperationHistorySection:View {
    var model:AppModel
    var search:String
    var onlyOpen:Bool
    private struct Receipt:Identifiable{let id:UUID;let title:String;let shop:String;let status:String;let date:Date;let detail:JSONValue;let error:String?}
    private var receipts:[Receipt]{
        let api=model.adminQueue.proposals.filter{$0.status != "pending" && (model.selectedShopID==nil || $0.shopID==model.selectedShopID)}.map{Receipt(id:$0.id,title:$0.request.method+" /api/"+$0.request.path,shop:$0.shopName,status:$0.status,date:$0.createdAt,detail:$0.response ?? .object([:]),error:$0.error)}
        let workflows=model.automationQueue.operations.filter{$0.status != "pending" && (model.selectedShopID==nil || $0.shopID==model.selectedShopID)}.map{Receipt(id:$0.id,title:$0.title,shop:$0.shopName,status:$0.status,date:$0.createdAt,detail:.object(["steps":.object($0.checkpoints),"result":$0.result ?? .null]),error:$0.error)}
        return (api+workflows).filter{(!onlyOpen || ["executing","uncertain","needs_review"].contains($0.status)) && (search.isEmpty || ($0.title+" "+$0.shop).localizedCaseInsensitiveContains(search))}.sorted{$0.date>$1.date}
    }
    var body:some View{if !receipts.isEmpty{DisclosureGroup(T("API, Medien, Plugins und Kampagnen")+" (\(receipts.count))"){LazyVStack(alignment:.leading,spacing:14){ForEach(Array(receipts.prefix(100))){receipt in VStack(alignment:.leading,spacing:10){HStack{Text(receipt.title).font(.headline);Spacer();StatusPill(text:T(receipt.status),color:receipt.status=="applied" ? .green:.orange)};Text(receipt.shop+" · "+localizedDate(receipt.date,date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary);if let error=receipt.error{Text(error).font(.caption).foregroundStyle(.orange)};DisclosureGroup(T("Ergebnis und Nachweis")){Text(receipt.detail.pretty).font(.system(size:11,design:.monospaced)).textSelection(.enabled)}}.padding(18).background(Theme.surface.opacity(0.6),in:RoundedRectangle(cornerRadius:10))}}}.font(.callout)}}
}
