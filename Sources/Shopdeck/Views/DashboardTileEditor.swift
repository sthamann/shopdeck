import SwiftUI
import ShopdeckCore
struct DashboardTileEditor:View {
    var model:AppModel
    @Environment(\.dismiss) private var dismiss
    @LocalState<DashboardTile> private var tile:DashboardTile
    init(model:AppModel,tile:DashboardTile){self.model=model;_tile=LocalState(initialValue:tile)}
    var body:some View {
        VStack(alignment:.leading,spacing:20){Text(T("Widget konfigurieren")).font(.title2.bold());Text(T(tile.widget.title)).foregroundStyle(.secondary)
            Form {
                Toggle(T("Globale Shopauswahl verwenden"),isOn:Binding(get:{tile.shopIDs==nil},set:{tile.shopIDs=$0 ? nil:Set(model.dashboardShops.map(\.id))}))
                if tile.shopIDs != nil {ForEach(model.dashboardUniverseShops){shop in Toggle(shop.name,isOn:Binding(get:{tile.shopIDs?.contains(shop.id)==true},set:{if $0{tile.shopIDs?.insert(shop.id)}else{tile.shopIDs?.remove(shop.id)}}))}}
                Toggle(T("Shops einzeln im Widget anzeigen"),isOn:$tile.showShops)
                Picker(T("Währung"),selection:Binding(get:{tile.currency ?? "global"},set:{tile.currency=$0=="global" ? nil:$0})){Text(T("Globale Währung")).tag("global");ForEach(model.analytics.currencies,id:\.self){Text($0).tag($0)}}
                Toggle(T("Globale Verkaufskanäle verwenden"),isOn:Binding(get:{tile.channelKeys==nil},set:{tile.channelKeys=$0 ? nil:Set(model.availableChannels.map(\.key))}))
                if tile.channelKeys != nil {ForEach(model.availableChannels,id:\.key){channel in Toggle((model.workspace.shops.first{$0.id==channel.shopID}?.name ?? "")+" · "+channel.name,isOn:Binding(get:{tile.channelKeys?.contains(channel.key)==true},set:{if $0{tile.channelKeys?.insert(channel.key)}else{tile.channelKeys?.remove(channel.key)}}))}}
            }.formStyle(.grouped)
            HStack{Button(T("Abbrechen")){dismiss()};Spacer();Button(T("Speichern")){var config=model.dashboardConfiguration;var items=config.effectiveTiles;if let i=items.firstIndex(where:{$0.id==tile.id}){items[i]=tile};config.tiles=items;model.saveDashboard(config);dismiss()}.buttonStyle(.borderedProminent)}
        }.padding(26).frame(width:600,height:650)
    }
}
