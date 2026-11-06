import SwiftUI
import ShopdeckCore
import UniformTypeIdentifiers

struct RecordsView: View {
    @Bindable var model: AppModel
    @AppStorage("pageSize") private var pageSize = 50
    @AppStorage("maxServerRecords") private var maximumRecords=1000
    @FocusState private var searchFocused: Bool
    @LocalState<String?> private var exportError: String?
    @LocalState<Bool> private var exporting = false
    @LocalState<Task<Void, Never>?> private var exportTask = nil
    @LocalState<Bool> private var savingView = false
    @LocalState<PickingSelection?> private var pickingSelection = nil
    @LocalState<OrderDocumentSelection?> private var documentSelection = nil
    @LocalState<BulkSelection?> private var bulkSelection = nil
    @LocalState<Bool> private var configuring = false
    @LocalState<Set<String>> private var selection: Set<String> = []
    @LocalState<[KeyPathComparator<ShopRecord>]> private var sortOrder = [KeyPathComparator(\ShopRecord.sortTitle)]
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) { recordHeading.fixedSize(); Spacer(minLength: 12); listActions.fixedSize() }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 12) { recordHeading; listActions.labelStyle(.iconOnly).fixedSize() }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if exporting {
                HStack { ProgressView().controlSize(.small); Text(T("Export wird mit deinen Filtern und Spalten vorbereitet …")).font(.caption); Spacer(); Button(T("Abbrechen")) { exportTask?.cancel() } }.padding(12).background(Theme.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
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
            if model.destination == .orders && !selection.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack { Text("\(selectedRecords.count) " + T("Bestellungen ausgewählt")); Spacer(); orderActions }.fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 10) { Text("\(selectedRecords.count) " + T("Bestellungen ausgewählt")); orderActions }
                }.font(.system(size: 12)).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Theme.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { searchBox.frame(width: 210); shopSelector.frame(width: 160); channelSelector.frame(width: 150); currencySelector; dateSelector.frame(width: 150); resultCount }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 10) {
                    HStack { searchBox; shopSelector.frame(maxWidth: 190) }
                    HStack { channelSelector; currencySelector; Spacer(minLength: 0) }; dateSelector.frame(maxWidth: 240)
                    resultCount
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
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
        .task(id: model.query) { try? await Task.sleep(for: .milliseconds(300)); if !Task.isCancelled { if !model.preservingRestoredPage || model.restoredQuery != model.query { model.page = 1 }; model.preservingRestoredPage = false; model.restoredQuery = nil; await model.loadRecords() } }
        .onChange(of: model.lowStockOnly) { _, _ in model.page = 1; Task { await model.loadRecords() } }
        .onChange(of: model.statusFilter) { _, _ in model.page = 1; Task { await model.loadRecords() } }
        .onChange(of: model.selectedShopID) { _, _ in selection = [];model.page=1 }
        .onChange(of: model.listShopIDs) { _, _ in selection = []; model.page = 1; Task { await model.loadRecords() } }
        .onChange(of:model.listChannelKey){_,_ in model.page=1;Task{await model.loadRecords()}}
        .onChange(of:model.listCurrency){_,_ in model.page=1;Task{await model.loadRecords()}}
        .task{await model.loadSalesChannels()}
        .onChange(of: model.destination) { _, _ in selection = [] }
        .onChange(of: model.records.map(\.id)) { _, ids in selection.formIntersection(ids) }
        .onChange(of:maximumRecords){_,_ in model.page=1;Task{await model.loadRecords()}}
        .onChange(of: pageSize) { _, _ in model.page = 1; Task { await model.loadRecords() } }
        .onChange(of: model.activeFilters) { _, _ in model.page = 1; Task { await model.loadRecords() } }
        .onDisappear { exportTask?.cancel() }
        .sheet(item: $pickingSelection) { PickingListView(model: model, orders: $0.orders) }
        .sheet(item: $documentSelection) { OrderDocumentsView(model: model, orders: $0.orders) }
        .sheet(item: $bulkSelection) { frozen in BulkProductEditView(model: model, records: frozen.records) }
        .sheet(isPresented: $configuring) { ListConfigurationView(model: model, entity: model.destination.entity) }
        .background(Button("") { searchFocused = true }.keyboardShortcut("f").hidden())
    }
    private var orderActions: some View {
        HStack {
            Button(T("Auswahl aufheben")) { selection = [] }
            Button { pickingSelection = .init(orders: selectedRecords) } label: { Label(T("Pickliste"), systemImage: "checklist") }.disabled(selectedRecords.count > 200 || model.isLoading).help(T("Bis zu 200 ausgewählte Bestellungen"))
            Button { documentSelection = .init(orders: selectedRecords) } label: { Label(T("Dokumente öffnen"), systemImage: "doc.richtext") }.disabled(selectedRecords.count > 200 || model.isLoading).help(T("Bis zu 200 ausgewählte Bestellungen"))
        }
    }
    private var recordHeading: some View { PageTitle(title: model.currentSavedView?.name ?? model.destination.title, subtitle: T("Shopübergreifend suchen. Direkt weiterarbeiten.")) }
    private var listActions: some View {
        HStack(spacing: 10) {
                Menu { Button(T("Standardansicht")) { model.query="";model.activeFilters=[];model.lowStockOnly=false;model.statusFilter="all";model.listShopIDs=nil;model.listChannelKey=nil;model.listCurrency=nil;model.recordSort=RecordSort.defaults(model.destination.entity) }; ForEach(model.workbench.savedViews.filter { $0.destination == model.destination.rawValue }) { preset in Button(preset.name) { model.openSavedView(preset) } }; Divider(); Menu(T("Ansicht entfernen")) { ForEach(model.workbench.savedViews.filter { $0.destination == model.destination.rawValue }) { preset in Button(preset.name) { model.removeSavedView(preset) } } } } label: { Label(T("Ansichten"),systemImage:"rectangle.stack") }
                Button { savingView.toggle() } label: { Label(T("Ansicht speichern"), systemImage: "bookmark") }
                Button { configuring = true } label: { Label(T("Liste anpassen"), systemImage: "slider.horizontal.3") }
                Menu {
                    Button(T("Angezeigte Seite exportieren")) { exportCSV(all: false) }
                    Button(T("Gefilterte Treffer exportieren") + " · " + T("maximal") + " \(maximumRecords)") { exportCSV(all: true) }
                } label: { Label(T("CSV exportieren"), systemImage: "square.and.arrow.up") }.disabled(model.records.isEmpty || exporting || model.isLoading)
        }
    }
    private var searchBox: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(T("Suchen …"), text: $model.query).textFieldStyle(.plain).focused($searchFocused)
            if !model.query.isEmpty { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
        }.padding(10).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }
    private var shopSelector: some View {
        Menu {
            Button(T("Alle Shops anzeigen")) { model.selectedShopID = nil; model.listShopIDs = nil }
            Divider()
            ForEach(model.workspace.shops) { shop in
                Toggle(shop.name, isOn: Binding(get: { model.listShopIDs?.contains(shop.id) ?? (model.selectedShopID == nil || model.selectedShopID == shop.id) }, set: { _ in model.toggleListShop(shop.id) }))
            }
        } label: { Label(model.listShopSelectionTitle, systemImage: "storefront").lineLimit(1) }.help(T("Shop"))
    }
    private var channelSelector: some View {
        Picker(T("Verkaufskanal"), selection: $model.listChannelKey) {
            Text(T("Alle Verkaufskanäle")).tag(nil as String?)
            ForEach(model.availableChannels.filter { (model.selectedShopID == nil || $0.shopID == model.selectedShopID) && (model.listShopIDs?.contains($0.shopID) ?? true) }, id: \.key) { channel in
                Text((model.selectedShopID == nil ? (model.workspace.shops.first { $0.id == channel.shopID }?.name ?? "") + " · " : "") + channel.name).tag(Optional(channel.key))
            }
        }.labelsHidden().help(T("Verkaufskanal")).accessibilityLabel(T("Verkaufskanal"))
    }
    @ViewBuilder private var currencySelector: some View {
        if model.destination == .orders {
            Picker(T("Währung"), selection: $model.listCurrency) {
                Text(T("Alle Währungen")).tag(nil as String?)
                ForEach(Array(Set(model.availableChannels.flatMap(\.currencies))).sorted(), id: \.self) { Text($0).tag(Optional($0)) }
            }.labelsHidden().frame(width: 110).help(T("Währung")).accessibilityLabel(T("Währung"))
        }
    }
    private var dateSelector: some View {
        Picker(T(model.destination == .orders ? "Bestellzeitraum" : "Erstellt im Zeitraum"), selection: Binding(get: { model.recordDateRange }, set: { model.setRecordDateRange($0) })) {
            Text(T("Alle Zeiträume")).tag(nil as RecordDateRange?)
            ForEach(RecordDateRange.allCases) { Text(T($0.title)).tag(Optional($0)) }
        }.labelsHidden().accessibilityLabel(T("Zeitraum")).help(T(model.destination == .orders ? "Bestellzeitraum" : "Erstellt im Zeitraum"))
    }
    private var resultCount: some View { Text("\(model.recordTotal) " + T("Ergebnisse")).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize() }
    private var quickFilters:[RecordFilter] {model.listConfiguration.filters + model.activeFilters.filter {active in active.operation != "dateRange" && !model.listConfiguration.filters.contains{$0.id==active.id}}}
    private var selectedRecords: [ShopRecord] { model.records.filter { selection.contains($0.id) } }
    private var dataTable: some View {
        let entity = model.destination.entity
        let columns=(entity=="product" && model.listConfiguration.showProductThumbnails != false ? [RecordColumn("__image",T("Bild"),width:54)]:[])+model.listConfiguration.columns
        return RecordTableView(records: model.records, columns: columns, selection: $selection, search: { searchFocused=true }, open: { model.editingRecord = $0 }, sort:model.recordSort,sortChanged:{model.sortRecords($0)},columnsChanged: { columns in var configuration = model.workbench.lists?[entity] ?? .standard(entity); configuration.columns = columns.filter{$0.field != "__image"}; model.saveListConfiguration(configuration, entity: entity) })
    }
    private func primary(_ r: ShopRecord) -> String { switch model.destination { case .orders: return "#" + (r.data["orderNumber"].string ?? ""); case .customers: return (r.data["firstName"].string ?? "") + " " + (r.data["lastName"].string ?? ""); default: return r.data.at("name").string ?? "–" } }
    private func secondary(_ r: ShopRecord) -> String { switch model.destination { case .orders: return dateLabel(r.data["orderDateTime"]); case .customers: return r.data["email"].string ?? ""; default: return r.data["productNumber"].string ?? "" } }
    private func exportCSV(all: Bool) {
        let entity = model.destination.entity, term = model.query, sort = model.recordSort
        let status = model.statusFilter, low = model.lowStockOnly, limit = min(max(maximumRecords, 1), 10000)
        let channel: CommerceChannelReference?
        do { channel = try CommerceChannelReference.resolve(model.listChannelKey) }
        catch { model.error = error.localizedDescription; return }
        let shops = model.scopedShops.filter { (model.listShopIDs?.contains($0.id) ?? true) && (channel == nil || $0.id == channel!.shopID) }
        let currency = model.listCurrency
        var filters: [UUID: [RecordFilter]] = [:]
        for shop in shops {
            var values = model.activeFilters
            if let channel { values.append(.init(name: "Channel", field: entity == "product" ? "visibilities.salesChannelId" : "salesChannelId", value: channel.id)) }
            if entity == "order", let currency { values.append(.init(name: "Currency", field: "currency.isoCode", value: currency)) }
            filters[shop.id] = values
        }
        let columns = model.listConfiguration.columns.map { RecordColumn($0.field, T($0.title), width: $0.width) }
        let visible = model.records.map { FederatedRecord(shop: $0.shop, data: $0.data) }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "shopdeck-\(entity)-" + (all ? "filtered" : "page-\(model.page)") + ".csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exporting = true
        exportTask = Task { @MainActor in
            defer { exporting = false; exportTask = nil }
            do {
                var rows = visible, capped = false
                if all {
                    let result = try await model.client.searchAcrossShops(shops, entity: entity, term: term, page: 1, pageSize: limit, maximum: limit, sort: sort, lowStock: low, status: status, filters: filters)
                    guard result.failures.isEmpty else { throw ShopdeckError.message(result.failures.joined(separator: "\n")) }
                    rows = result.rows; capped = result.capped
                }
                try Task.checkCancellation()
                let frozen = rows
                let data = await Task.detached { RecordCSV.encode(rows: frozen, columns: columns) }.value
                try Task.checkCancellation()
                try data.write(to: url, options: .atomic)
                model.notice = "\(rows.count) " + T("Datensätze exportiert") + (capped ? " · " + T("Ladegrenze erreicht. Für weitere Treffer Filter eingrenzen oder die Grenze erhöhen.") : "")
            } catch is CancellationError { }
            catch { model.error = error.localizedDescription }
        }
    }
}

private struct BulkSelection: Identifiable { let id = UUID(); let records: [ShopRecord] }
