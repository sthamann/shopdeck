import SwiftUI
import ShopdeckCore
struct BulkProposalReviewView:View {
    var model:AppModel
    @Environment(\.dismiss) private var dismiss
    private let products:[ChangeProposal]
    private let actions:[AdminAPIProposal]
    private let operations:[AutomationOperation]
    @LocalState<Set<UUID>> private var selected:Set<UUID>
    @LocalState<[UUID:[String:JSONValue]]> private var before=[:]
    @LocalState<[UUID:String]> private var problems=[:]
    @LocalState<Bool> private var preparing=true
    @LocalState<Bool> private var running=false
    @LocalState<Bool> private var stop=false
    @LocalState<Int> private var completed=0
    @LocalState<String?> private var failure:String?
    @LocalState<Bool> private var finished=false
    private let batchID=UUID()
    init(model:AppModel){self.model=model;products=model.workspace.proposals.filter{$0.status=="pending" && (model.selectedShopID==nil || $0.shopID==model.selectedShopID)};actions=model.adminQueue.proposals.filter{$0.status=="pending" && (model.selectedShopID==nil || $0.shopID==model.selectedShopID)};operations=model.automationQueue.operations.filter{$0.status=="pending" && (model.selectedShopID==nil || $0.shopID==model.selectedShopID)};_selected=LocalState(initialValue:Set(products.map(\.id)+actions.map(\.id)+operations.map(\.id)))}
    var body:some View {
        VStack(alignment:.leading,spacing:18){
            Text(T("Änderungen gemeinsam freigeben")).font(.title2.bold())
            Text(T("Prüfe Auswahl, Zielshops und Werte. Jeder Vorgang wird einzeln protokolliert. Bei einem Fehler hält die Übernahme an.")).font(.callout).foregroundStyle(.secondary)
            if preparing{ProgressView(T("Aktuelle Produktwerte werden geladen …"))}
            if running || finished{ProgressView(value:Double(completed),total:Double(max(selected.count,1)));Text("\(completed) / \(selected.count) "+T("übernommen")).font(.caption)}
            ScrollView{LazyVStack(alignment:.leading,spacing:14){
                ForEach(products){proposal in VStack(alignment:.leading,spacing:8){Toggle(isOn:selection(proposal.id)){Text(proposal.productName).fontWeight(.semibold)}.disabled(running || finished || problems[proposal.id] != nil);Text((model.workspace.shops.first{$0.id==proposal.shopID}?.name ?? "")+" · "+proposal.reason).font(.caption).foregroundStyle(.secondary);ForEach(proposal.changes.keys.sorted(),id:\.self){key in HStack{Text(T(key)).frame(width:85,alignment:.leading);Text((before[proposal.id]?[key] ?? .null).localizedDisplayString).foregroundStyle(.secondary).lineLimit(3);Image(systemName:"arrow.right");Text(proposal.changes[key]!.localizedDisplayString).lineLimit(3)}.font(.system(size:12))};if let error=problems[proposal.id]{Text(error).font(.caption).foregroundStyle(.orange)}};Divider()}
                ForEach(operations){operation in Toggle(isOn:selection(operation.id)){VStack(alignment:.leading){Text(operation.title).fontWeight(.semibold);Text(operation.shopName+" · "+operation.kind).font(.caption);AutomationPlanView(operation:operation,store:model.store)}}.disabled(running || finished);Divider()}
                ForEach(actions){proposal in VStack(alignment:.leading,spacing:8){Toggle(proposal.request.method+" /api/"+proposal.request.path,isOn:selection(proposal.id)).disabled(running || finished);Text(proposal.shopName+" · "+proposal.reason).font(.caption).foregroundStyle(.secondary);DisclosureGroup(T("Anfrage anzeigen")){Text(proposal.request.body.pretty).font(.system(size:11,design:.monospaced)).textSelection(.enabled)}};Divider()}
            }}
            if let failure{Text(failure).font(.callout).foregroundStyle(.orange).textSelection(.enabled)}
            HStack{Button(running ? T("Nach aktuellem Vorgang stoppen"):T("Schließen")){if running{stop=true}else{dismiss()}}.disabled(stop && running);Spacer();if !finished{Text("\(selected.count) "+T("ausgewählt")).font(.caption);Button(T("Auswahl übernehmen")){Task{await apply()}}.buttonStyle(.borderedProminent).disabled(preparing || running || selected.isEmpty)}}
        }.padding(26).frame(width:800,height:700).interactiveDismissDisabled(running).task{await prepare()}
    }
    private func selection(_ id:UUID)->Binding<Bool>{Binding(get:{selected.contains(id)},set:{if $0{selected.insert(id)}else{selected.remove(id)}})}
    private func prepare()async {
        defer{preparing=false}
        for proposal in products {if Task.isCancelled{return};guard let shop=model.workspace.shops.first(where:{$0.id==proposal.shopID})else{problems[proposal.id]=T("Shop entfernt");selected.remove(proposal.id);continue};do{let current=try await model.client.detail(shop,entity:"product",id:proposal.productID);let values=Dictionary(uniqueKeysWithValues:proposal.changes.keys.map{($0,current[$0])});if let expected=proposal.expectedBefore,expected != values{throw ShopdeckError.message(T("Das Produkt wurde seit dem Vorschlag geändert. Bitte einzeln prüfen."))};before[proposal.id]=values}catch{problems[proposal.id]=error.localizedDescription;selected.remove(proposal.id)}}
    }
    private func apply()async {
        running=true;defer{running=false;finished=true}
        for proposal in products where selected.contains(proposal.id){if stop{break};let success=await model.resolve(proposal,apply:true,reviewedBefore:before[proposal.id],refreshAfter:false,notify:false,origin:"ai-batch:"+batchID.uuidString);if !success{failure=model.changeFailure ?? T("Übernahme angehalten.");return};completed+=1}
        if !stop{for proposal in actions where selected.contains(proposal.id){if stop{break};let success=await model.resolveAdminAPI(proposal,apply:true,refreshAfter:false,notify:false);if !success{failure=model.changeFailure ?? T("Übernahme angehalten.");return};completed+=1}}
        if !stop{for operation in operations where selected.contains(operation.id){if stop{break};if !(await model.resolveOperation(operation,apply:true,refreshAfter:false)){failure=model.changeFailure;return};completed+=1}}
        if stop{failure=T("Angehalten. Nicht übernommene Vorschläge bleiben offen.")}
        await model.refresh()
    }
}
