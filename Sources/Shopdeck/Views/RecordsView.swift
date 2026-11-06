import SwiftUI
import ShopdeckCore
import UniformTypeIdentifiers

struct RecordsView: View {
    @Bindable var model: AppModel
    @AppStorage("pageSize") private var pageSize = 50
    @AppStorage("maxServerRecords") private var maximumRecords=1000
    @FocusState private var searchFocused: Bool
    @LocalState<String?> private var exportError: String?
    @LocalState<Bool> private var savingView = false
    @LocalState<BulkSelection?> private var bulkSelection = nil
    @LocalState<Bool> private var configuring = false
    @LocalState<Set<String>> private var selection: Set<String> = []
    @LocalState<[KeyPathComparator<ShopRecord>]> private var sortOrder = [KeyPathComparator(\ShopRecord.sortTitle)]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                PageTitle(title: model.currentSavedView?.name ?? model.destination.title, subtitle: T("Shopübergreifend suchen. Direkt weiterarbeiten."))
                Spacer()
                Menu { Button(T("Standardansicht")) { model.query="";model.activeFilters=[];model.lowStockOnly=false;model.statusFilter="all" }; ForEach(model.workbench.savedViews.filter { $0.destination == model.destination.rawValue }) { preset in Button(preset.name) { model.openSavedView(preset) } }; Divider(); Menu(T("Ansicht entfernen")) { ForEach(model.workbench.savedViews.filter { $0.destination == model.destination.rawValue }) { preset in Button(preset.name) { model.removeSavedView(preset) } } } } label: { Label(T("Ansichten"),systemImage:"rectangle.stack") }
                Button { savingView.toggle() } label: { Label(T("Ansicht speichern"), systemImage: "bookmark") }
                Button { configuring = true } label: { Label(T("Liste anpassen"), systemImage: "slider.horizontal.3") }
                Button { exportCSV() } label: { Label(T("CSV exportieren"), systemImage: "square.and.arrow.up") }.disabled(model.records.isEmpty)
            }
            if savingView { SaveViewEditor(model: model, onClose: { savingView = false }) }
            if model.destination == .products && !selection.isEmpty {
                HStack(spacing: 16) {
                    Label("\(selectedRecords.count) " + T("Produkte ausgewählt"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.blue)
                    Spacer()
                    Button(T("Auswahl aufheben")) { selection = [] }
                    Button { bulkSelection = BulkSelection(records: selectedRecords) } label: { Label(T("Gemeinsam bearbeiten"), systemImage: "square.stack.3d.up") }.buttonStyle(.borderedProminent).disabled(selectedRecords.isEmpty || model.isLoading)
                }.font(.system(size: 12)).padding(14).background(Theme.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField(T("Suchen …"), text: $model.query).textFieldStyle(.plain).focused($searchFocused); if !model.query.isEmpty { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) } }.padding(10).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                Picker(T("Shop"), selection: $model.selectedShopID) { Text(T("Alle Shops")).tag(nil as UUID?); ForEach(model.workspace.shops) { Text($0.name).tag(Optional($0.id)) } }.frame(width: 230)
                Picker(T("Verkaufskanal"),selection:$model.listChannelKey){Text(T("Alle Verkaufskanäle")).tag(nil as String?);ForEach(model.availableChannels.filter{model.selectedShopID==nil || $0.shopID==model.selectedShopID},id:\.key){channel in Text((model.selectedShopID==nil ? (model.workspace.shops.first{$0.id==channel.shopID}?.name ?? "")+" · ":"")+channel.name).tag(Optional(channel.key))}}.frame(maxWidth:190)
                if model.destination == .orders{Picker(T("Währung"),selection:$model.listCurrency){Text(T("Alle Währungen")).tag(nil as String?);ForEach(Array(Set(model.availableChannels.flatMap(\.currencies))).sorted(),id:\.self){Text($0).tag(Optional($0))}}.frame(width:150)}
                Text("\(model.recordTotal) \(T("Ergebnisse"))").font(.system(size: 12)).foregroundStyle(.secondary).frame(minWidth: 100)
            }
            if !quickFilters.isEmpty {
                ScrollView(.horizontal) { HStack { ForEach(quickFilters) { filter in Toggle(filter.name, isOn: Binding(get: { model.activeFilters.contains { $0.id == filter.id } }, set: { enabled in if enabled { model.activeFilters.append(filter) } else { model.activeFilters.removeAll { $0.id == filter.id } } })).toggleStyle(.button) }; if !model.activeFilters.isEmpty { Button(T("Filter zurücksetzen")) { model.activeFilters = []; model.lowStockOnly = false; model.statusFilter = "all" } } } }
            }
            if model.lowStockOnly || model.statusFilter != "all" { HStack { Text(T("Filter aus gespeicherter Ansicht") + ": " + (model.lowStockOnly ? T("Bestand ≤ 5") : T(model.statusFilter))).font(.caption); Button(T("Filter zurücksetzen")) { model.lowStockOnly = false; model.statusFilter = "all" } } }
            ZStack {
                dataTable.disabled(model.isLoading).opacity(model.isLoading ? 0.35 : 1)
                if model.isLoading { ProgressView().padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
                else if model.records.isEmpty { ContentUnavailableView(model.query.isEmpty ? T("Noch keine Daten") : T("Keine Treffer"), systemImage: model.destination.icon, description: Text(T("Wähle einen Shop oder passe die Suche an."))).allowsHitTesting(false) }
            }
            HStack {
                Text(T("Serverseitig sortiert und gefiltert")+" · "+T("Eingabetaste öffnet Details")).font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button { model.page -= 1; Task { await model.loadRecords() } } label: { Image(systemName: "chevron.left") }.disabled(model.page <= 1)
                Text("\(T("Seite")) \(model.page)").font(.system(size: 12)).monospacedDigit()
                Button { model.page += 1; Task { await model.loadRecords() } } label: { Image(systemName: "chevron.right") }.disabled(!model.recordHasNext || model.isLoading)
            }
            if model.recordCapped{HStack{Text(T("Ergebnisgrenze erreicht")+": \(maximumRecords). "+T("Erhöhe die Ladegrenze in den Einstellungen oder grenze die Suche ein.")).font(.caption).foregroundStyle(.secondary);Spacer()}}
        }.padding(24)
        .task(id: model.query) { try? await Task.sleep(for: .milliseconds(300)); if !Task.isCancelled { model.page = 1; await model.loadRecords() } }
        .onChange(of: model.lowStockOnly) { _, _ in model.page = 1; Task { await model.loadRecords() } }
        .onChange(of: model.statusFilter) { _, _ in model.page = 1; Task { await model.loadRecords() } }
        .onChange(of: model.selectedShopID) { _, _ in selection = [];model.page=1 }
        .onChange(of:model.listChannelKey){_,_ in model.page=1;Task{await model.loadRecords()}}
        .onChange(of:model.listCurrency){_,_ in model.page=1;Task{await model.loadRecords()}}
        .task{await model.loadSalesChannels()}
        .onChange(of: model.destination) { _, _ in selection = [] }
        .onChange(of: model.records.map(\.id)) { _, ids in selection.formIntersection(ids) }
        .onChange(of:maximumRecords){_,_ in model.page=1;Task{await model.loadRecords()}}
        .onChange(of: pageSize) { _, _ in model.page = 1; Task { await model.loadRecords() } }
        .onChange(of: model.activeFilters) { _, _ in model.page = 1; Task { await model.loadRecords() } }
        .sheet(item: $bulkSelection) { frozen in BulkProductEditView(model: model, records: frozen.records) }
        .sheet(isPresented: $configuring) { ListConfigurationView(model: model, entity: model.destination.entity) }
        .background(Button("") { searchFocused = true }.keyboardShortcut("f").hidden())
    }
    private var quickFilters:[RecordFilter] {model.listConfiguration.filters + model.activeFilters.filter {active in !model.listConfiguration.filters.contains{$0.id==active.id}}}
    private var selectedRecords: [ShopRecord] { model.records.filter { selection.contains($0.id) } }
    private var dataTable: some View {
        let entity = model.destination.entity
        let columns=(entity=="product" && model.listConfiguration.showProductThumbnails != false ? [RecordColumn("__image",T("Bild"),width:54)]:[])+model.listConfiguration.columns
        return RecordTableView(records: model.records, columns: columns, selection: $selection, search: { searchFocused=true }, open: { model.editingRecord = $0 }, sort:model.recordSort,sortChanged:{model.sortRecords($0)},columnsChanged: { columns in var configuration = model.workbench.lists?[entity] ?? .standard(entity); configuration.columns = columns.filter{$0.field != "__image"}; model.saveListConfiguration(configuration, entity: entity) })
    }
    private func primary(_ r: ShopRecord) -> String { switch model.destination { case .orders: return "#" + (r.data["orderNumber"].string ?? ""); case .customers: return (r.data["firstName"].string ?? "") + " " + (r.data["lastName"].string ?? ""); default: return r.data.at("name").string ?? "–" } }
    private func secondary(_ r: ShopRecord) -> String { switch model.destination { case .orders: return dateLabel(r.data["orderDateTime"]); case .customers: return r.data["email"].string ?? ""; default: return r.data["productNumber"].string ?? "" } }
    private func exportCSV() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.commaSeparatedText]; panel.nameFieldStringValue = "shopdeck-\(model.destination.entity)-page-\(model.page).csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        func quoted(_ s: String) -> String { let safe = ["=", "+", "-", "@", "\t", "\r"].contains(where: { s.hasPrefix($0) }) ? "'" + s : s; return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let lines = ["shop,id,title,detail"] + model.records.map { [ $0.shop.name, $0.data["id"].string ?? "", primary($0), secondary($0) ].map(quoted).joined(separator: ",") }
        do { try lines.joined(separator: "\r\n").write(to: url, atomically: true, encoding: .utf8); model.notice = T("Die angezeigte Seite wurde exportiert.") } catch { model.error = error.localizedDescription }
    }
}

private struct BulkSelection: Identifiable { let id = UUID(); let records: [ShopRecord] }
