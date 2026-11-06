import SwiftUI
import ShopdeckCore

struct ContentView: View {
    @Bindable var model: AppModel
    var showSidebar = true
    var body: some View {
        Group {
            if showSidebar { NavigationSplitView { SidebarView(model: model).navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 270) } detail: { detail } }
            else { detail }
        }
    }
    private var detail: some View {
            VStack(spacing: 0) {
                topBar
                Divider()
                Group {
                    switch model.destination {
                    case .overview: DashboardView(model: model)
                    case .admin: AdministrationView(model: model)
                    case .frontends:StorefrontsView(model:model)
                    case .products, .orders, .customers: RecordsView(model: model)
                    case .ai: AISetupView(model: model)
                    case .followups: FollowUpsView(model: model)
                    case .changes: ChangesView(model: model)
                    case .history: ProductHistoryView(model: model)
                    case .notifications: NotificationRulesView(model: model)
                    case .updates: UpdatesView(model: model)
                    case .activity: ActivityView(model: model)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if let notice = model.notice { HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text(notice); Spacer(); Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }.padding(14).background(.bar) }
            }
        .sheet(isPresented: $model.showingAddShop) { ShopFormView(model: model, existing: nil) }
        .sheet(item: $model.editShop) { ShopFormView(model: model, existing: $0) }
        .sheet(item: $model.editingRecord) { RecordDetailView(model: model, record: $0) }
        .sheet(isPresented: $model.showGroupSheet) { GroupFormView(model: model) }
        .sheet(isPresented: $model.showingCommandPalette) { CommandPaletteView(model: model) }
        .alert(T("Das hat nicht geklappt"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        .onChange(of: model.selectedShopID) { _, _ in model.page = 1; Task { if [.products,.orders,.customers].contains(model.destination){await model.loadRecords()}else if model.destination == .overview,model.analytics.loadedAt==nil{await model.loadAnalytics()} } }
        .onChange(of: model.destination) { _, _ in model.page = 1; Task { await model.loadRecords() } }
    }
    private var topBar: some View {
        HStack(spacing: 12) {
            if model.selectedShopID != nil {Button{model.selectedShopID=nil}label:{Label(T("Alle Shops anzeigen"),systemImage:"chevron.backward")}.buttonStyle(.borderless).font(.system(size:12,weight:.medium))}
            Image(systemName: model.destination.icon).foregroundStyle(Theme.blue)
            Text(model.destination.title).fontWeight(.semibold)
            Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.tertiary)
            Menu{Button(T("Alle Shops anzeigen")){model.selectedShopID=nil;model.listShopIDs=nil};Divider();ForEach(model.workspace.shops){shop in Button(shop.name){model.selectedShopID=shop.id}}}label:{Text(model.selectedShop?.name ?? T("Alle Shops")).lineLimit(1)}.menuStyle(.borderlessButton).fixedSize()
            Spacer()
            if model.isDemo { StatusPill(text: T("Demodaten"), color: .orange) }
            if let shop = model.selectedShop, model.destination != .admin { Button { model.openAdministration(shop) } label: { Label(T("Administration"), systemImage: "macwindow") }.buttonStyle(.bordered) }
            Button { model.showingCommandPalette = true } label: { Image(systemName: "magnifyingglass") }.buttonStyle(.borderless).help(T("Schnellsuche") + " · ⌘K")
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise").symbolEffect(.pulse, options: .repeating, isActive: model.isRefreshing) }.buttonStyle(.borderless).help(T("Aktualisieren")).disabled(model.isRefreshing)
            Button { model.showingAddShop = true } label: { Label(T("Shop hinzufügen"), systemImage: "plus") }.buttonStyle(.borderedProminent).controlSize(.regular)
        }.padding(.horizontal, 28).frame(height: 62)
    }
}

struct GroupFormView: View {
    var model: AppModel
    @LocalState<String> private var name = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View { VStack(alignment: .leading, spacing: 20) { Text(T("Neue Gruppe")).font(.title2.bold()); TextField(T("Name"), text: $name).textFieldStyle(.roundedBorder); HStack { Button(T("Abbrechen")) { dismiss() }; Spacer(); Button(T("Gruppe erstellen")) { model.mutate { $0.groups.append(ShopGroup(name: name.trimmingCharacters(in: .whitespacesAndNewlines))) }; dismiss() }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }.padding(28).frame(width: 380) }
}
