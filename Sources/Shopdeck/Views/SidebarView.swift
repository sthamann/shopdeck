import SwiftUI
import ShopdeckCore
import UniformTypeIdentifiers

struct SidebarDragReference:Codable,Transferable {
    enum Kind:String,Codable {case shop,group}
    let kind:Kind
    let id:UUID
    static var transferRepresentation:some TransferRepresentation {CodableRepresentation(contentType:UTType(exportedAs:"app.shopdeck.sidebar-reference"))}
}
struct SidebarView:View {
    @Bindable var model:AppModel
    @Environment(\.openShopWorkspace) private var openWorkspace
    @LocalState<Shop?> private var deleting:Shop? = nil
    @LocalState<UUID?> private var renaming:UUID? = nil
    @LocalState<String> private var draftName=""
    @LocalState<String?> private var dropTarget:String? = nil
    @FocusState private var renameFocused:Bool
    var body:some View {
        VStack(spacing:0) {
            HStack(spacing:10) {if let icon=Bundle.main.url(forResource:"AppIcon",withExtension:"icns").flatMap({NSImage(contentsOf:$0)}){Image(nsImage:icon).resizable().scaledToFit().frame(width:36,height:36)};Text("shopdeck").font(.system(size:22,weight:.bold,design:.rounded));Spacer()}.padding(.horizontal,20).padding(.top,10).padding(.bottom,14)
            Button{model.showingCommandPalette=true}label:{HStack{Image(systemName:"magnifyingglass");Text(T("Schnellsuche"));Spacer();Text("⌘K").font(.system(size:10)).foregroundStyle(.tertiary)}.font(.system(size:12)).foregroundStyle(.secondary).padding(10).background(.quaternary.opacity(0.3),in:RoundedRectangle(cornerRadius:8))}.buttonStyle(.plain).padding(.horizontal,16).padding(.bottom,12)
            ScrollView {
                VStack(alignment:.leading,spacing:4) {
                    ForEach([Destination.overview,.admin,.frontends,.products,.orders,.customers,.followups,.changes,.history]){navRow($0)}
                    Divider().padding(.vertical,12)
                    HStack {Text(T("DEINE SHOPS")).font(.system(size:10,weight:.semibold)).tracking(1.2).foregroundStyle(.secondary);Spacer();Menu{Button(T("Shop hinzufügen")){model.showingAddShop=true};Button(T("Neue Gruppe")){model.showGroupSheet=true}}label:{Image(systemName:"plus")}.menuStyle(.borderlessButton).fixedSize()}.padding(.horizontal,10).padding(.bottom,7)
                    Button{model.selectedShopID=nil;model.listShopIDs=nil}label:{HStack(spacing:11){Image(systemName:"square.stack").frame(width:26);Text(T("Alle Shops"));Spacer();Text("\(model.workspace.shops.count)").foregroundStyle(.secondary)}.padding(.horizontal,10).padding(.vertical,9).contentShape(Rectangle())}.buttonStyle(.plain).foregroundStyle(model.selectedShopID==nil ? Theme.blue:.primary).background(model.selectedShopID==nil || dropTarget=="ungrouped" ? Theme.blue.opacity(0.10):.clear,in:RoundedRectangle(cornerRadius:7)).onDrop(of:[UTType.text],isTargeted:targetBinding("ungrouped")){providers in acceptDrop(providers,before:nil,group:nil)}
                    shopRows(nil)
                    ForEach(model.workspace.groups){group in
                        HStack(spacing:8){Image(systemName:"folder");Text(group.name).lineLimit(1);Spacer();Text("\(model.workspace.shops.filter{$0.groupID==group.id}.count)").font(.system(size:10)).foregroundStyle(.secondary);Menu{Button(T("Gruppe löschen"),role:.destructive){model.mutate{state in state.groups.removeAll{$0.id==group.id};for i in state.shops.indices where state.shops[i].groupID==group.id{state.shops[i].groupID=nil}}}}label:{Image(systemName:"ellipsis")}.menuStyle(.borderlessButton).fixedSize()}.font(.system(size:11,weight:.medium)).foregroundStyle(.secondary).padding(.horizontal,10).padding(.vertical,10).background(dropTarget==group.id.uuidString ? Theme.blue.opacity(0.14):.clear,in:RoundedRectangle(cornerRadius:7)).contentShape(Rectangle()).onDrag{NSItemProvider(object:("shopdeck:group:"+group.id.uuidString) as NSString)}.onDrop(of:[UTType.text],isTargeted:targetBinding(group.id.uuidString)){providers in acceptDrop(providers,before:nil,group:group.id)}
                        if !model.workspace.shops.contains(where:{$0.groupID==group.id}) {Text(T("Shops hierher ziehen")).font(.system(size:11)).foregroundStyle(.secondary).frame(maxWidth:.infinity,minHeight:34,alignment:.leading).padding(.horizontal,12).background(dropTarget==group.id.uuidString ? Theme.blue.opacity(0.1):.clear,in:RoundedRectangle(cornerRadius:7)).onDrop(of:[UTType.text],isTargeted:targetBinding(group.id.uuidString)){providers in acceptDrop(providers,before:nil,group:group.id)}}
                        shopRows(group.id)
                    }
                    Button{model.showingAddShop=true}label:{Label(T("Shop verbinden"),systemImage:"plus.circle").font(.system(size:12)).foregroundStyle(.secondary).padding(10)}.buttonStyle(.plain)
                    Divider().padding(.vertical,12)
                    ForEach(Array(Destination.allCases.suffix(4))){navRow($0)}
                }.padding(.horizontal,12)
            }
            VStack(alignment:.leading,spacing:13) {
                VStack(alignment:.leading,spacing:10) {
                    Link(destination:URL(string:"https://www.shopware.com/en/community/community-edition/")!){HStack(alignment:.top,spacing:10){Image(systemName:"shippingbox.fill").font(.system(size:21)).foregroundStyle(Theme.blue);VStack(alignment:.leading,spacing:4){Text("Community Edition").font(.system(size:12,weight:.semibold));Text(T("Shopware. Kostenlos und Open Source.")).font(.system(size:10)).foregroundStyle(.secondary)};Spacer(minLength:0);Image(systemName:"arrow.up.right").font(.system(size:9)).foregroundStyle(.secondary)}}.buttonStyle(.plain)
                    Button(T("Lokal ausprobieren")){model.startWithLocalShop=true;model.showingAddShop=true}.font(.system(size:11,weight:.medium)).buttonStyle(.borderless).foregroundStyle(Theme.blue)
                }.padding(12).frame(maxWidth:.infinity,alignment:.leading).background(Theme.blue.opacity(0.075),in:RoundedRectangle(cornerRadius:10))
                HStack{SettingsLink{Label(T("Einstellungen"),systemImage:"gearshape")}.buttonStyle(.plain);Spacer();Text(AppVersion.current).foregroundStyle(.tertiary)}.font(.system(size:11))
            }.padding(14)
        }.background(.bar)
        .alert(T("Shop entfernen?"),isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}})){Button(T("Abbrechen"),role:.cancel){deleting=nil};Button(T("Entfernen"),role:.destructive){if let deleting{model.removeShop(deleting)};deleting=nil}}message:{Text(T("Der Shop wird nur aus Shopdeck entfernt. Die Daten im Shop und ein lokaler Container bleiben erhalten."))}
    }
    private func navRow(_ destination:Destination)->some View {
        Button{if [.overview,.admin,.followups,.changes,.notifications,.updates,.ai,.activity].contains(destination){model.selectedShopID=nil};model.destination=destination}label:{HStack(spacing:11){Image(systemName:destination.icon).font(.system(size:15)).frame(width:22);Text(destination.title).font(.system(size:13,weight:model.destination==destination ? .semibold:.regular));Spacer();if destination == .followups,model.dueFollowUpCount>0{Text("\(model.dueFollowUpCount)").font(.system(size:10,weight:.bold)).foregroundStyle(.orange)};if destination == .changes,model.pendingCount>0{Text("\(model.pendingCount)").font(.system(size:10,weight:.bold)).padding(.horizontal,6).padding(.vertical,2).background(Theme.blue,in:Capsule()).foregroundStyle(.white)}}.padding(.horizontal,10).padding(.vertical,9).contentShape(Rectangle())}.buttonStyle(.plain).foregroundStyle(model.destination==destination ? Theme.blue:.primary).background(model.destination==destination ? Theme.blue.opacity(0.13):.clear,in:RoundedRectangle(cornerRadius:7))
    }
    @ViewBuilder private func shopRows(_ group:UUID?)->some View {
        ForEach(model.workspace.shops.filter{$0.groupID==group}){shop in
            Group {
                if renaming==shop.id {
                    HStack(spacing:10){ShopIcon(shop:shop,size:27);TextField(T("Shopname"),text:$draftName).textFieldStyle(.roundedBorder).focused($renameFocused).onSubmit{commitRename(shop)}.onExitCommand{renaming=nil}.onAppear{renameFocused=true}}.padding(.horizontal,10).padding(.vertical,8)
                } else {
                    Button{if [.overview,.admin].contains(model.destination){model.openAdministration(shop)}else{model.selectedShopID=shop.id}}label:{
                        HStack(spacing:10){ShopIcon(shop:shop,size:27);VStack(alignment:.leading,spacing:3){Text(shop.name).font(.system(size:12,weight:.medium)).lineLimit(1);Text(shop.isDemo ? T("Demodaten"):T(shop.environment)).font(.system(size:10)).foregroundStyle(.secondary)};Spacer();if model.connectionErrors[shop.id] != nil{Image(systemName:"exclamationmark.circle.fill").foregroundStyle(.orange).font(.system(size:10))}}.padding(.horizontal,10).padding(.vertical,8).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(shop.name)
                }
            }.background(model.selectedShopID==shop.id ? Theme.blue.opacity(0.13):.clear,in:RoundedRectangle(cornerRadius:7)).overlay(alignment:.top){if dropTarget==shop.id.uuidString{RoundedRectangle(cornerRadius:1).fill(Theme.blue).frame(height:2)}}
                .onDrag{NSItemProvider(object:("shopdeck:shop:"+shop.id.uuidString) as NSString)}
                .onDrop(of:[UTType.text],isTargeted:targetBinding(shop.id.uuidString)){providers in acceptDrop(providers,before:shop.id,group:shop.groupID)}
                .contextMenu {
                    Button(T("Umbenennen")){draftName=shop.name;renaming=shop.id}
                    Button(T("In neuem Tab öffnen")){openWorkspace(shop,false)}
                    Button(T("Nebeneinander öffnen")){openWorkspace(shop,true)}
                    Button(T("Administration in Shopdeck öffnen")){model.openAdministration(shop)}
                    ShopStorefrontMenu(model:model,shop:shop)
                    Button(T("Shopeinstellungen")){model.editShop=shop}
                    Button(T("Schlüsselbundzugriff freigeben")){Task{await model.requestKeychainAccess(shop)}}
                    Menu(T("In Gruppe verschieben")){Button(T("Ohne Gruppe")){model.moveShop(shop.id,before:nil,group:nil)};ForEach(model.workspace.groups){g in Button(g.name){model.moveShop(shop.id,before:nil,group:g.id)}}}
                    Button(T("Nach oben")){if let index=model.workspace.shops.firstIndex(where:{$0.id==shop.id}),index>0{model.moveShop(shop.id,before:model.workspace.shops[index-1].id,group:shop.groupID)}}
                    Button(T("Entfernen"),role:.destructive){deleting=shop}
                }
        }
    }
    private func targetBinding(_ id:String)->Binding<Bool>{Binding(get:{dropTarget==id},set:{dropTarget=$0 ? id:nil})}
    private func acceptDrop(_ providers:[NSItemProvider],before:UUID?,group:UUID?)->Bool {
        guard let provider=providers.first else{return false}
        _ = provider.loadObject(ofClass:NSString.self){value,_ in
            guard let text=value as? String else{return};let parts=text.split(separator:":");guard parts.count==3,parts[0]=="shopdeck",let kind=SidebarDragReference.Kind(rawValue:String(parts[1])),let id=UUID(uuidString:String(parts[2]))else{return}
            Task{@MainActor in _ = drop([.init(kind:kind,id:id)],before:before,group:group)}
        };return true
    }
    private func commitRename(_ shop:Shop){do{try model.renameShop(shop.id,name:draftName);renaming=nil}catch{model.error=error.localizedDescription}}
    private func drop(_ items:[SidebarDragReference],before:UUID?,group:UUID?)->Bool {
        guard let item=items.first else{return false};dropTarget=nil
        if item.kind == .shop {guard model.workspace.shops.contains(where:{$0.id==item.id}),item.id != before else{return false};model.moveShop(item.id,before:before,group:group);return true}
        guard let group,item.id != group else{return false};model.mutate{state in guard let from=state.groups.firstIndex(where:{$0.id==item.id}),let target=state.groups.firstIndex(where:{$0.id==group})else{return};let moved=state.groups.remove(at:from);state.groups.insert(moved,at:min(target,state.groups.count))};return true
    }
}
