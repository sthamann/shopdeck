import SwiftUI
import ShopdeckCore

private struct PaletteAction: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let run: () -> Void
}

private struct PaletteSection: Identifiable {
    let id: String
    let title: String
    let actions: [PaletteAction]
}

struct CommandPaletteView: View {
    var model: AppModel
    var onExecute: (@escaping () -> Void) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @LocalState<String> private var query = ""
    @LocalState<String?> private var selected: String? = nil
    @FocusState private var focused: Bool

    private var term: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var sections: [PaletteSection] {
        let searchTerm = term
        let shopNames = Dictionary(model.workspace.shops.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let bookmarks = model.bookmarks.compactMap { item -> PaletteAction? in
            guard let name = shopNames[item.shopID] else { return nil }
            return .init(id: "bookmark-" + item.id, title: item.title, detail: name + " · " + item.reference, icon: "star") {
                model.openBookmark(item)
            }
        }
        let followUps = model.followUps.filter { $0.completedAt == nil && shopNames[$0.shopID] != nil }
            .sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
            .map { item in
                PaletteAction(id: "followup-\(item.id)", title: item.title, detail: shopNames[item.shopID] ?? "", icon: "bookmark") {
                    model.openFollowUp(item)
                }
            }
        let addShop = PaletteAction(id: "add-shop", title: T("Shop hinzufügen"), detail: T("Verbinden oder lokal mit Docker starten"), icon: "plus.circle") {
            model.showingAddShop = true
        }
        if searchTerm.isEmpty {
            return [
                .init(id: "suggested", title: T("Direkt loslegen"), actions: [.overview, .orders, .products, .followups, .ai].map(destinationAction) + [addShop]),
                .init(id: "bookmarks", title: T("Lesezeichen"), actions: Array(bookmarks.prefix(5))),
                .init(id: "followups", title: T("Wiedervorlagen"), actions: Array(followUps.prefix(3)))
            ].filter { !$0.actions.isEmpty }
        }

        var actions = Destination.allCases.map(destinationAction) + [addShop]
        actions += MerchantFocus.allCases.map { focus in
            .init(id: "focus-" + focus.rawValue, title: T(focus.title), detail: T("Arbeitsvorrat öffnen"), icon: focus.icon) {
                model.openFocus(focus)
            }
        }
        actions += model.workbench.savedViews.map { view in
            .init(id: "view-\(view.id)", title: view.name, detail: T("Gespeicherte Ansicht"), icon: "rectangle.stack") {
                model.openSavedView(view)
            }
        }
        actions += model.workspace.shops.map { shop in
            .init(id: "shop-\(shop.id)", title: shop.name, detail: shop.isDemo ? T("Demodaten") : shop.host, icon: "storefront") {
                model.selectedShopID = shop.id
            }
        }
        actions.append(.init(id: "all-shops", title: T("Alle Shops"), detail: T("Gemeinsame Übersicht"), icon: "square.stack") {
            model.selectedShopID = nil
            model.listShopIDs = nil
            model.destination = .overview
        })
        actions.append(.init(id: "refresh", title: T("Aktualisieren"), detail: T("Daten der gewählten Shops neu laden"), icon: "arrow.clockwise") {
            Task { await model.refresh() }
        })

        let words = searchTerm.split(whereSeparator: \.isWhitespace).map(String.init)
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let matches = (actions + bookmarks + followUps).filter { action in
            let searchable = action.title + " " + action.detail
            return words.allSatisfy { searchable.range(of: $0, options: options) != nil }
        }
        let exact = matches.filter { $0.title.compare(searchTerm, options: options) == .orderedSame }
        let exactIDs = Set(exact.map(\.id))
        let prefixes = matches.filter {
            !exactIDs.contains($0.id) && $0.title.range(of: searchTerm, options: options.union(.anchored)) != nil
        }
        let direct = exact + prefixes
        let directIDs = Set(direct.map(\.id))
        let recordDestinations: [Destination] = [.products, .orders, .customers]
        let orderedSearches = recordDestinations.filter { $0 == model.destination } +
            recordDestinations.filter { $0 != model.destination }
        let searches = orderedSearches.map { destination in
            PaletteAction(id: "search-" + destination.rawValue, title: destination.title + ": “\(searchTerm)”",
                          detail: model.selectedShop?.name ?? T("Alle Shops"), icon: "magnifyingglass") {
                model.searchRecords(destination, term: searchTerm)
            }
        }
        return [
            .init(id: "exact", title: T("Direkte Treffer"), actions: direct),
            .init(id: "search", title: T("In Shops suchen"), actions: searches),
            .init(id: "matches", title: T("Weitere Treffer"), actions: matches.filter { !directIDs.contains($0.id) })
        ].filter { !$0.actions.isEmpty }
    }

    private func destinationAction(_ destination: Destination) -> PaletteAction {
        .init(id: "destination-" + destination.rawValue, title: destination.title,
              detail: T("Arbeitsbereich öffnen"), icon: destination.icon) {
            model.openWorkspaceDestination(destination)
        }
    }

    var body: some View {
        let groups = sections
        let rows = groups.flatMap(\.actions)
        VStack(spacing: 0) {
            HStack(spacing: 13) {
                Image(systemName: "magnifyingglass").font(.title2).foregroundStyle(.secondary)
                TextField(T("Shops, Aktionen oder Datensätze suchen"), text: $query)
                    .font(.title3)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { execute(rows.first { $0.id == selected } ?? rows.first) }
                    .onKeyPress(.upArrow) { move(-1, in: rows); return .handled }
                    .onKeyPress(.downArrow) { move(1, in: rows); return .handled }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Label(T("Suche löschen"), systemImage: "xmark.circle.fill").labelStyle(.iconOnly)
                    }.buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 20).padding(.vertical, 17)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(groups) { section in
                            Text(section.title)
                                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                .accessibilityAddTraits(.isHeader)
                                .padding(.leading, 11).padding(.top, 9).padding(.bottom, 3)
                            ForEach(section.actions) { action in actionRow(action).id(action.id) }
                        }
                    }.padding(.horizontal, 9).padding(.bottom, 9)
                }
                .frame(height: 354)
                .onChange(of: selected) { _, value in
                    if let value { proxy.scrollTo(value) }
                }
            }
            Divider()
            HStack(spacing: 14) {
                Text(model.selectedShop?.name ?? T("Alle Shops")).lineLimit(1)
                Spacer()
                Text("↑ ↓ " + T("Auswählen"))
                Text("↵ " + T("Öffnen"))
                Text("esc " + T("Schließen"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 20).padding(.vertical, 11)
        }
        .frame(width: 576)
        .onAppear { selected = rows.first?.id; focused = true }
        .onChange(of: query) { _, _ in selected = rows.first?.id }
        .onMoveCommand { direction in
            if direction == .up { move(-1, in: rows) }
            if direction == .down { move(1, in: rows) }
        }
        .onExitCommand { dismiss() }
    }

    private func actionRow(_ action: PaletteAction) -> some View {
        let isSelected = selected == action.id
        return Button { execute(action) } label: {
            HStack(spacing: 11) {
                Image(systemName: action.icon)
                    .font(.system(size: 15))
                    .foregroundStyle(isSelected ? Theme.blue : Color.secondary)
                    .frame(width: 25)
                VStack(alignment: .leading, spacing: 3) {
                    Text(action.title).font(.callout.weight(.medium)).lineLimit(1)
                    Text(action.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if isSelected { Image(systemName: "return").font(.caption).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(WorkspaceRowStyle())
        .background(isSelected ? Theme.blue.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isSelected)
    }

    private func move(_ offset: Int, in rows: [PaletteAction]) {
        guard !rows.isEmpty else { return }
        let index = rows.firstIndex { $0.id == selected } ?? 0
        selected = rows[min(max(0, index + offset), rows.count - 1)].id
    }

    private func execute(_ action: PaletteAction?) {
        guard let action else { return }
        onExecute(action.run)
        dismiss()
    }
}
