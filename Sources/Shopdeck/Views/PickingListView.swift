import SwiftUI
import ShopdeckCore
import UniformTypeIdentifiers

struct PickingSelection: Identifiable { let id = UUID(); let orders: [ShopRecord] }
struct PickingListView: View {
    let model: AppModel
    let orders: [ShopRecord]
    @Environment(\.dismiss) private var dismiss
    @LocalState<PickingList?> private var batch = nil
    @LocalState<Bool> private var loading = true
    @LocalState<String?> private var error = nil
    @LocalState<String> private var search = ""
    @LocalState<UUID?> private var shopID = nil
    @LocalState<Bool> private var outstanding = false
    @LocalState<Set<String>> private var checked = []
    @LocalState<String?> private var selection = nil
    @LocalState<[KeyPathComparator<PickingItem>]> private var sorting = [.init(\PickingItem.shopName), .init(\PickingItem.sku)]
    @LocalState<UUID> private var reloadID = UUID()
    @LocalState<ShopRecord?> private var detail = nil
    @LocalState<Bool> private var exporting = false
    @LocalState<Task<Void, Never>?> private var exportTask = nil
    private var rows: [PickingItem] {
        (batch?.items ?? []).filter { item in
            (shopID == nil || item.shop.id == shopID) && (!outstanding || !checked.contains(item.id)) &&
            (search.isEmpty || [item.title, item.sku, item.shop.name, item.orderSummary].joined(separator: " ").localizedCaseInsensitiveContains(search))
        }.sorted(using: sorting)
    }
    private var chosen: PickingItem? { batch?.items.first { $0.id == selection } }
    private var headings: [String] { [T("Shop"), T("Produktnummer"), T("Produkt"), T("Anzahl"), T("Bestellungen"), T("Geprüft")] }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "checklist").font(.system(size: 26)).foregroundStyle(Theme.blue)
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(T("Pickliste")).font(.title2.bold()); if orders.contains(where: { $0.shop.isDemo }) { Text(T("Demodaten")).font(.caption).foregroundStyle(.orange) } }
                    Text(T("Artikel aus ausgewählten Bestellungen gesammelt bereitstellen.")).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button { reloadID = UUID() } label: { Image(systemName: "arrow.clockwise") }.disabled(loading || exporting).help(T("Frisch aus Shopware laden"))
                Button(T("Schließen")) { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(22)
            Divider()
            if let batch {
                HStack(spacing: 24) {
                    Label("\(batch.orders.count) " + T("Bestellungen"), systemImage: "bag")
                    Label("\(batch.items.count) " + T("Artikel"), systemImage: "shippingbox")
                    Text("\(batch.units) " + T("Stück"))
                    Spacer()
                    Text("\(checked.count) / \(batch.items.count) " + T("geprüft")).monospacedDigit().foregroundStyle(Theme.blue)
                }.font(.system(size: 13, weight: .medium)).padding(.horizontal, 22).padding(.vertical, 17)
                HStack(spacing: 14) {
                    TextField(T("In der Pickliste suchen"), text: $search).textFieldStyle(.roundedBorder)
                    Picker(T("Shop"), selection: $shopID) {
                        Text(T("Alle Shops")).tag(nil as UUID?)
                        ForEach(Array(Dictionary(grouping: batch.orders, by: { $0.shop.id }).values.compactMap { $0.first?.shop }).sorted { $0.name < $1.name }) { Text($0.name).tag(Optional($0.id)) }
                    }.frame(width: 230)
                    Toggle(T("Nur ungeprüfte Artikel"), isOn: $outstanding).toggleStyle(.checkbox)
                }.padding(.horizontal, 22).padding(.bottom, 16)
                if batch.excludedOrders > 0 || batch.excludedLines > 0 {
                    Text("\(batch.excludedOrders) " + T("stornierte Bestellungen ausgelassen") + " · \(batch.excludedLines) " + T("digitale oder sonstige Positionen ausgelassen")).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.bottom, 12)
                }
                Table(rows, selection: $selection, sortOrder: $sorting) {
                    TableColumn(T("Geprüft")) { item in
                        Toggle(T("Geprüft"), isOn: Binding(get: { checked.contains(item.id) }, set: { value in if value { checked.insert(item.id) } else { checked.remove(item.id) } })).labelsHidden().accessibilityLabel(item.title + " · " + T("Geprüft"))
                    }.width(60)
                    TableColumn(T("Shop"), value: \.shopName).width(min: 100, ideal: 130)
                    TableColumn(T("Produktnummer"), value: \.sku) { Text($0.sku.isEmpty ? T("Ohne Artikelnummer") : $0.sku).textSelection(.enabled) }.width(min: 120, ideal: 150)
                    TableColumn(T("Produkt"), value: \.title).width(min: 200, ideal: 300)
                    TableColumn(T("Anzahl"), value: \.quantity) { Text(String($0.quantity)).monospacedDigit().fontWeight(.semibold) }.width(70)
                }.onKeyPress(.space) { toggleSelected(); return selection == nil ? .ignored : .handled }
                    .onKeyPress(.return) { if let order = chosen?.allocations.first?.order { open(order); return .handled }; return .ignored }
                if rows.isEmpty { Text(T("Keine passenden Artikel in dieser Pickliste.")).foregroundStyle(.secondary).padding(16) }
                if let item = chosen {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.title + " · " + String(item.quantity) + " " + T("Stück")).font(.headline)
                        ScrollView(.horizontal) {
                            HStack(spacing: 10) { ForEach(item.allocations) { allocation in Button { open(allocation.order) } label: { Text("#" + allocation.order.number + " · " + String(allocation.quantity) + " " + T("Stück")) } } }
                        }
                    }.padding(.horizontal, 22).padding(.vertical, 15)
                }
                HStack { Text(T("Leerzeichen markiert. Eingabetaste öffnet die zugehörige Bestellung.")).font(.caption).foregroundStyle(.secondary); Spacer(); Button(T("Prüfmarkierungen zurücksetzen")) { checked = [] }.disabled(checked.isEmpty) }.padding(.horizontal, 22).padding(.vertical, 12)
            } else if loading { ProgressView(T("Bestellungen und Positionen werden vollständig geladen …")).frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { ContentUnavailableView(T("Pickliste konnte nicht erstellt werden"), systemImage: "shippingbox", description: Text(error ?? "")).frame(maxWidth: .infinity, maxHeight: .infinity) }
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(T("Markierungen gelten für diese Pickliste. Bestellstatus und Bestand bleiben unverändert.")).font(.caption).foregroundStyle(.secondary)
                    if let date = batch?.loadedAt { Text(T("Geladen") + " " + date.formatted(date: .omitted, time: .shortened) + " · \(rows.count) " + T("sichtbare Artikel exportieren")).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                if exporting { ProgressView().controlSize(.small); Button(T("Abbrechen")) { exportTask?.cancel() } }
                Button(T("CSV exportieren")) { export(pdf: false) }.disabled(rows.isEmpty || exporting || loading)
                Button(T("PDF speichern")) { export(pdf: true) }.buttonStyle(.borderedProminent).disabled(rows.isEmpty || exporting || loading)
            }.padding(18)
            if let error, batch != nil { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal, 22).padding(.bottom, 14) }
        }.frame(width: 1040, height: 740)
            .task(id: reloadID) { await load() }
            .sheet(item: $detail) { RecordDetailView(model: model, record: $0) }
            .onDisappear { exportTask?.cancel() }
    }
    private func toggleSelected() { if let id = selection { if checked.contains(id) { checked.remove(id) } else { checked.insert(id) } } }
    private func open(_ order: PickingOrder) { detail = .init(shop: order.shop, data: .object(["id": .string(order.orderID)]), entity: "order") }
    private func load() async {
        loading = true; batch = nil; checked = []; error = nil; selection = nil; defer { loading = false }
        do { let value = try await model.client.pickingList(orders.map { .init(shop: $0.shop, data: $0.data) }); try Task.checkCancellation(); batch = value }
        catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
    private func export(pdf: Bool) {
        let frozen = rows, marks = checked, columns = headings, title = T("Pickliste")
        let subtitle = Date().formatted(date: .abbreviated, time: .shortened) + " · " + T("Ausgewählte Bestellungen") + (orders.contains(where: { $0.shop.isDemo }) ? " · " + T("Demodaten") : "")
        let panel = NSSavePanel(); panel.allowedContentTypes = pdf ? [.pdf] : [.commaSeparatedText]; panel.nameFieldStringValue = pdf ? "Shopdeck-Picking-List.pdf" : "Shopdeck-Picking-List.csv"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        exporting = true; error = nil
        exportTask = Task { @MainActor in
            defer { exporting = false; exportTask = nil }
            let worker = Task.detached { pdf ? try PickingList.pdf(items: frozen, checked: marks, title: title, subtitle: subtitle, headings: columns) : PickingList.csv(items: frozen, checked: marks, headings: columns) }
            do {
                let data = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                try Task.checkCancellation(); try data.write(to: destination, options: .atomic); model.notice = T("Pickliste gespeichert")
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}
