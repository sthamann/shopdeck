import SwiftUI
import ShopdeckCore

struct ContentView: View {
    @Bindable var model: AppModel
    var showSidebar = true
    @LocalState<(() -> Void)?> private var pendingCommand = nil
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
                if let notice = model.notice {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                        Text(notice).font(.callout)
                        Spacer()
                        Button { model.notice = nil } label: {
                            Label(T("Schließen"), systemImage: "xmark").labelStyle(.iconOnly)
                        }.buttonStyle(.borderless)
                    }.padding(.horizontal, 20).padding(.vertical, 10).background(.bar)
                }
            }
        .sheet(isPresented: $model.showingAddShop) { ShopFormView(model: model, existing: nil) }
        .sheet(item: $model.editShop) { ShopFormView(model: model, existing: $0) }
        .sheet(item: $model.editingRecord) { RecordDetailView(model: model, record: $0) }
        .sheet(isPresented: $model.showGroupSheet) { GroupFormView(model: model) }
        .sheet(isPresented: $model.showingCommandPalette, onDismiss: {
            let action = pendingCommand
            pendingCommand = nil
            action?()
        }) {
            CommandPaletteView(model: model) { pendingCommand = $0 }
        }
        .alert(T("Das hat nicht geklappt"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        .onChange(of: model.selectedShopID) { _, _ in model.page = 1; Task { if [.products,.orders,.customers].contains(model.destination){await model.loadRecords()}else if model.destination == .overview,model.analytics.loadedAt==nil{await model.loadAnalytics()} } }
        .onChange(of: model.destination) { _, _ in model.page = 1; Task { await model.loadRecords() } }
    }
    private var topBar: some View {
        HStack(spacing: 9) {
            Label(model.destination.title, systemImage: model.destination.icon)
                .font(.headline)
                .lineLimit(1)
                .layoutPriority(1)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            Menu {
                Button(T("Alle Shops anzeigen")) {
                    model.selectedShopID = nil
                    model.listShopIDs = nil
                }
                if !model.workspace.shops.isEmpty { Divider() }
                ForEach(model.workspace.shops) { shop in
                    Button {
                        model.selectedShopID = shop.id
                    } label: {
                        if model.selectedShopID == shop.id {
                            Label(shop.name, systemImage: "checkmark")
                        } else {
                            Text(shop.name)
                        }
                    }
                }
            } label: {
                Text(model.selectedShop?.name ?? T("Alle Shops"))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 175)
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: true, vertical: false)
            .help(model.selectedShop?.name ?? T("Alle Shops"))
            if model.selectedShopID != nil {
                Button { model.selectedShopID = nil } label: {
                    Label(T("Alle Shops anzeigen"), systemImage: "xmark.circle.fill").labelStyle(.iconOnly)
                }.buttonStyle(.borderless).foregroundStyle(.secondary).help(T("Alle Shops anzeigen"))
            }
            Spacer(minLength: 6)
            if model.isDemo { StatusPill(text: T("Demodaten"), color: .orange) }
            if let shop = model.selectedShop, model.destination != .admin {
                Button { model.openAdministration(shop) } label: {
                    ViewThatFits(in: .horizontal) {
                        Label(T("Administration"), systemImage: "macwindow").fixedSize()
                        Label(T("Administration"), systemImage: "macwindow").labelStyle(.iconOnly)
                    }
                }.help(T("Administration in Shopdeck öffnen"))
            }
            if !showSidebar {
                Menu {
                    Button(T("Schnellsuche")) { model.showingCommandPalette = true }
                    Button(T("Aktualisieren")) { Task { await model.refresh() } }.disabled(model.isRefreshing)
                    Button(T("Shop hinzufügen")) { model.showingAddShop = true }
                } label: {
                    Label(T("Aktionen"), systemImage: "ellipsis.circle").labelStyle(.iconOnly)
                }.menuStyle(.borderlessButton).fixedSize()
            }
        }.padding(.horizontal, 22).frame(height: 43)
    }
}

struct GroupFormView: View {
    var model: AppModel
    @LocalState<String> private var name = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View { VStack(alignment: .leading, spacing: 20) { Text(T("Neue Gruppe")).font(.title2.bold()); TextField(T("Name"), text: $name).textFieldStyle(.roundedBorder); HStack { Button(T("Abbrechen")) { dismiss() }; Spacer(); Button(T("Gruppe erstellen")) { model.mutate { $0.groups.append(ShopGroup(name: name.trimmingCharacters(in: .whitespacesAndNewlines))) }; dismiss() }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }.padding(28).frame(width: 380) }
}
