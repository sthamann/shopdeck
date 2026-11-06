import SwiftUI
import ShopdeckCore

struct FollowUpsView: View {
    @Bindable var model: AppModel
    @LocalState<String> private var search = ""
    @LocalState<String> private var scope = "open"
    @LocalState<RecordFollowUp?> private var editing = nil
    private var scoped: [RecordFollowUp] { model.followUps.filter { model.selectedShopID == nil || $0.shopID == model.selectedShopID } }
    private var items: [RecordFollowUp] {
        let end = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))!
        return scoped.filter { item in
            let status = scope == "done" ? item.completedAt != nil : item.completedAt == nil && (scope != "due" || item.dueAt.map { $0 < end } == true)
            let shop = model.workspace.shops.first { $0.id == item.shopID }?.name ?? ""
            return status && (search.isEmpty || (item.title + " " + item.reference + " " + item.note + " " + shop).localizedCaseInsensitiveContains(search))
        }.sorted { ($0.dueAt ?? .distantFuture, $0.createdAt) < ($1.dueAt ?? .distantFuture, $1.createdAt) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                PageTitle(title: T("Wiedervorlagen"), subtitle: T("Notizen behalten. Termine setzen. Nichts liegen lassen."))
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(scoped.filter { $0.completedAt == nil }.count)").font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(T("offene Aufgaben")).font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 18) {
                Picker(T("Anzeigen"), selection: $scope) { Text(T("Offen")).tag("open"); Text(T("Bis heute fällig")).tag("due"); Text(T("Erledigt")).tag("done") }.pickerStyle(.segmented).frame(maxWidth: 420)
                Spacer()
                TextField(T("Notiz, Nummer oder Shop suchen"), text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 310)
            }
            if items.isEmpty {
                ContentUnavailableView(T(!search.isEmpty ? "Keine Treffer" : scope == "done" ? "Noch nichts erledigt" : scope == "due" ? "Heute ist nichts fällig" : "Hier bleibt nichts vergessen"), systemImage: scope == "due" ? "checkmark.circle" : "bookmark.circle", description: Text(T("Öffne ein Produkt, eine Bestellung oder einen Kunden. Unter Notizen und Wiedervorlage kannst du den nächsten Schritt festhalten."))).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in row(item); Divider() }
                    }.padding(.horizontal, 18).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                }
            }
            Text(T("Privat auf diesem Mac gespeichert. Keine Änderung im Shop und keine Freigabe über MCP.")).font(.caption).foregroundStyle(.secondary)
        }.padding(26)
            .sheet(item: $editing) { item in
                VStack(alignment: .leading, spacing: 0) {
                    HStack { Text(T("Notizen und Wiedervorlage")).font(.title2.bold()); Spacer(); Button(T("Schließen")) { editing = nil }.keyboardShortcut(.cancelAction) }.padding(24)
                    Divider()
                    FollowUpEditor(model: model, item: item, saved: { editing = nil }).padding(24)
                }.frame(width: 620, height: 500)
            }
    }
    private func row(_ item: RecordFollowUp) -> some View {
        let shop = model.workspace.shops.first { $0.id == item.shopID }
        return HStack(alignment: .center, spacing: 15) {
            Button { model.completeFollowUp(item, completed: item.completedAt == nil) } label: {
                Image(systemName: item.completedAt == nil ? "circle" : "checkmark.circle.fill").font(.system(size: 21)).foregroundStyle(item.completedAt == nil ? Color.secondary : Theme.blue)
            }.buttonStyle(.plain).help(item.completedAt == nil ? T("Als erledigt markieren") : T("Wieder öffnen"))
            Button { model.openFollowUp(item) } label: {
                HStack(spacing: 13) {
                    if let shop { ShopIcon(shop: shop, size: 32) }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text((shop?.name ?? T("Shop nicht verbunden")) + " · " + T(item.entity == "product" ? "Produkt" : item.entity == "order" ? "Bestellung" : "Kunde") + (item.reference.isEmpty ? "" : " · " + item.reference)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        if !item.note.isEmpty { Text(item.note).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
            if let due = item.dueAt {
                Label(localizedDate(due), systemImage: item.isDue() ? "clock.badge.exclamationmark" : "calendar").font(.system(size: 11, weight: .medium)).foregroundStyle(item.isDue() ? Color.orange : Color.secondary)
            }
            Menu {
                Button(T("Notiz bearbeiten")) { editing = item }
                Button(T("Auf morgen verschieben")) { model.postponeFollowUp(item, days: 1) }
                Button(T("Um eine Woche verschieben")) { model.postponeFollowUp(item, days: 7) }
                Divider()
                Button(T("Datensatz öffnen")) { model.openFollowUp(item) }.disabled(shop == nil)
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().help(T("Weitere"))
        }.padding(.vertical, 18)
    }
}

struct FollowUpEditor: View {
    var model: AppModel
    let item: RecordFollowUp
    var saved: () -> Void = {}
    @LocalState<String> private var note: String
    @LocalState<Bool> private var scheduled: Bool
    @LocalState<Date> private var due: Date
    @LocalState<Bool> private var completed: Bool
    init(model: AppModel, item: RecordFollowUp, saved: @escaping () -> Void = {}) {
        self.model = model; self.item = item; self.saved = saved
        _note = LocalState(initialValue: item.note); _scheduled = LocalState(initialValue: item.dueAt != nil)
        _due = LocalState(initialValue: item.dueAt ?? Calendar.current.date(byAdding: .day, value: 1, to: Date())!)
        _completed = LocalState(initialValue: item.completedAt != nil)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(item.title).font(.headline).lineLimit(2)
            Text(T("Was ist der nächste Schritt?")).font(.system(size: 13, weight: .medium))
            TextEditor(text: $note).font(.system(size: 14)).frame(minHeight: 100, maxHeight: 200).padding(8).background(Theme.surface, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary)).accessibilityLabel(T("Notiz"))
            Toggle(T("Termin setzen"), isOn: $scheduled)
            if scheduled { DatePicker(T("Fällig am"), selection: $due).datePickerStyle(.compact); HStack { Button(T("Morgen")) { due = Calendar.current.date(byAdding: .day, value: 1, to: Date())! }; Button(T("In einer Woche")) { due = Calendar.current.date(byAdding: .day, value: 7, to: Date())! } }.controlSize(.small) }
            Toggle(T("Erledigt"), isOn: $completed)
            Spacer(minLength: 0)
            HStack(alignment: .center) {
                Text(T("Nur auf diesem Mac. Nicht im Shop oder für KI sichtbar.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button(T("Wiedervorlage speichern")) {
                    var next = item; next.note = note; next.dueAt = scheduled ? due : nil; next.completedAt = completed ? (item.completedAt ?? Date()) : nil
                    if model.saveFollowUp(next) { saved() }
                }.buttonStyle(.borderedProminent).disabled(note.count > 4000)
            }
            if note.count > 4000 { Text(T("Die Notiz darf höchstens 4.000 Zeichen enthalten.")).font(.caption).foregroundStyle(.orange) }
        }
    }
}
