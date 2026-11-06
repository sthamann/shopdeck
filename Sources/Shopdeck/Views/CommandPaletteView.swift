import SwiftUI
import ShopdeckCore

private struct PaletteAction: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let run: () -> Void
}
struct CommandPaletteView: View {
    var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @LocalState<String> private var query = ""
    @LocalState<String?> private var selected: String?
    @FocusState private var focused: Bool
    private var actions: [PaletteAction] {
        var all: [PaletteAction] = []
        let saved = query.isEmpty ? Array(model.bookmarks.prefix(20)) : model.bookmarks
        for item in saved where model.workspace.shops.contains(where: { $0.id == item.shopID }) {
            let detail = T("Lesezeichen") + " · " + (model.workspace.shops.first { $0.id == item.shopID }?.name ?? "") + " · " + item.reference
            all.append(PaletteAction(id: "bookmark-" + item.id, title: item.title, detail: detail, icon: "star", run: { model.openBookmark(item) }))
        }
        for item in model.followUps.filter({ $0.completedAt == nil }).sorted(by: { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }).prefix(20) {
            all.append(PaletteAction(id: "followup-\(item.id)", title: item.title, detail: T("Wiedervorlage") + " · " + (model.workspace.shops.first { $0.id == item.shopID }?.name ?? ""), icon: "bookmark", run: { model.openFollowUp(item) }))
        }
        for focus in MerchantFocus.allCases {
            all.append(PaletteAction(id: "focus-" + focus.rawValue, title: T(focus.title), detail: T("Arbeitsvorrat öffnen"), icon: focus.icon, run: { model.openFocus(focus) }))
        }
        for preset in model.workbench.savedViews {
            all.append(PaletteAction(id: "view-\(preset.id)", title: preset.name, detail: T("Gespeicherte Ansicht"), icon: "bookmark", run: { model.openSavedView(preset) }))
        }
        for shop in model.workspace.shops {
            all.append(PaletteAction(id: "shop-\(shop.id)", title: shop.name, detail: shop.isDemo ? T("Demodaten") : shop.host, icon: "storefront", run: { model.selectedShopID = shop.id; model.destination = .overview }))
        }
        all.append(PaletteAction(id: "all-shops", title: T("Alle Shops"), detail: T("Gemeinsame Übersicht"), icon: "square.stack", run: { model.selectedShopID = nil; model.listShopIDs = nil; model.destination = .overview }))
        for destination in Destination.allCases {
            all.append(PaletteAction(id: "destination-\(destination.rawValue)", title: destination.title, detail: T("Arbeitsbereich öffnen"), icon: destination.icon, run: { model.destination = destination }))
        }
        all.append(PaletteAction(id: "add-shop", title: T("Shop hinzufügen"), detail: T("Verbinden oder lokal mit Docker starten"), icon: "plus.circle", run: { model.showingAddShop = true }))
        all.append(PaletteAction(id: "low-stock", title: T("Knappe Bestände prüfen"), detail: T("Arbeitsvorrat öffnen"), icon: "shippingbox", run: { model.openFocus(.lowStock) }))
        all.append(PaletteAction(id: "refresh", title: T("Aktualisieren"), detail: T("Daten der gewählten Shops neu laden"), icon: "arrow.clockwise", run: { Task { await model.refresh() } }))
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { return all }
        let matching = all.filter { ($0.title + " " + $0.detail).localizedCaseInsensitiveContains(clean) }
        let searches = [Destination.products, .orders, .customers].map { destination in
            PaletteAction(id: "search-\(destination.rawValue)", title: destination.title + ": “\(clean)”", detail: model.selectedShop?.name ?? T("Alle Shops"), icon: "magnifyingglass", run: { model.searchRecords(destination, term: clean) })
        }
        return matching + searches
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.blue).font(.system(size: 22))
                TextField(T("Wohin möchtest du?"), text: $query).font(.system(size: 23, weight: .medium)).textFieldStyle(.plain).focused($focused).onSubmit { execute() }
                Button { dismiss() } label: { Text("esc").font(.system(size: 10, weight: .medium)).padding(5).background(.quaternary, in: RoundedRectangle(cornerRadius: 4)) }.buttonStyle(.plain).help(T("Schließen"))
            }.padding(24)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(actions) { action in
                            Button { execute(action) } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: action.icon).font(.system(size: 17)).foregroundStyle(Theme.blue).frame(width: 25)
                                    VStack(alignment: .leading, spacing: 5) { Text(action.title).font(.system(size: 14, weight: .medium)).lineLimit(1); Text(action.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                                    Spacer()
                                    if selected == action.id { Image(systemName: "return").font(.system(size: 12)).foregroundStyle(.secondary) }
                                }.padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
                            }.buttonStyle(.plain).background(selected == action.id ? Theme.blue.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 8)).id(action.id)
                        }
                    }.padding(10)
                }.frame(height: 390).onChange(of: selected) { _, value in if let value { proxy.scrollTo(value, anchor: .center) } }
            }
            Divider()
            HStack { Text(T("Tippen zum Suchen")); Spacer(); Text("↑ ↓ " + T("Auswählen") + "    ↵ " + T("Öffnen")) }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 13)
        }.frame(width: 650)
            .onAppear { selected = actions.first?.id; focused = true }
            .onChange(of: query) { _, _ in selected = actions.first?.id }
            .onMoveCommand { direction in
                let index = actions.firstIndex { $0.id == selected } ?? 0
                if direction == .down, !actions.isEmpty { selected = actions[min(index + 1, actions.count - 1)].id }
                if direction == .up, !actions.isEmpty { selected = actions[max(index - 1, 0)].id }
            }.onExitCommand { dismiss() }
    }
    private func execute(_ action: PaletteAction? = nil) {
        guard let chosen = action ?? actions.first(where: { $0.id == selected }) ?? actions.first else { return }
        dismiss()
        // Let the palette close before presenting another sheet.
        Task { @MainActor in await Task.yield(); chosen.run() }
    }
}
