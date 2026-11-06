import SwiftUI
import ShopdeckCore

struct AdminAPIReviewSection:View {
    var model:AppModel
    @LocalState<AdminAPIProposal?> private var confirming:AdminAPIProposal? = nil
    @LocalState<Bool> private var busy=false
    private var proposals:[AdminAPIProposal]{model.adminQueue.proposals.filter{model.selectedShopID==nil || $0.shopID==model.selectedShopID}.reversed()}
    var body:some View {
        if !proposals.isEmpty {
            VStack(alignment:.leading,spacing:18) {
                Text(T("Allgemeine Admin API Aktionen")).font(.title3.bold())
                ForEach(proposals){proposal in
                    VStack(alignment:.leading,spacing:12){HStack{Text(proposal.request.method+" /api/"+proposal.request.path).font(.system(size:13,weight:.semibold));Spacer();Text(T(proposal.status)).font(.caption).foregroundStyle(.secondary)};Text(proposal.shopName+" · "+proposal.reason).font(.system(size:12)).foregroundStyle(.secondary);DisclosureGroup(T("Anfrage anzeigen")){Text(proposal.request.body.pretty).font(.system(size:11,design:.monospaced)).textSelection(.enabled)};if let error=proposal.error{Text(error).font(.caption).foregroundStyle(.orange)};if proposal.status=="pending"{HStack{Button(T("Ablehnen")){Task{await model.resolveAdminAPI(proposal,apply:false)}};Spacer();Button(T("Prüfen und übernehmen")){confirming=proposal}.buttonStyle(.borderedProminent)}}
                    }
                    Divider()
                }
            }.padding(.bottom,12)
            .sheet(item:$confirming){proposal in VStack(alignment:.leading,spacing:20){Text(T("API Aktion freigeben")).font(.title2.bold());Text(proposal.shopName).font(.headline);Text(proposal.request.method+" /api/"+proposal.request.path).font(.system(size:13,weight:.semibold));ScrollView{Text(proposal.request.body.pretty).font(.system(size:12,design:.monospaced)).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading)};Text(T("Diese Aktion wird mit den Rechten der Integration im ausgewählten Shop ausgeführt.")).font(.caption).foregroundStyle(.secondary);HStack{Button(T("Abbrechen")){confirming=nil};Spacer();Button(T("Jetzt ausführen")){Task{busy=true;await model.resolveAdminAPI(proposal,apply:true);busy=false;confirming=nil}}.buttonStyle(.borderedProminent).disabled(busy)}}.padding(28).frame(width:700,height:580)}
        }
    }
}
