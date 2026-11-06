import SwiftUI
import ShopdeckCore

struct NotificationRulesView: View {
    @Bindable var model: AppModel
    @LocalState<Bool> private var adding = false
    @LocalState<OrderRule?> private var editing: OrderRule?
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top) { PageTitle(title: T("Nur das, was dich interessiert."), subtitle: T("Erfahre von neuen Bestellungen, die zu deinen Regeln passen.")); Spacer(); Button { adding = true } label: { Label(T("Neue Regel"), systemImage: "plus") }.buttonStyle(.borderedProminent) }
            Panel { HStack(spacing: 18) { Image(systemName: "bell.badge").font(.system(size: 28)).foregroundStyle(Theme.blue); VStack(alignment: .leading, spacing: 7) { Text(T("Mitteilungen auf deinem Mac")).font(.headline); Text(T("Prüfung jede Minute, solange Shopdeck läuft. Beim ersten Start werden bestehende Bestellungen als Ausgangspunkt gespeichert.")).font(.system(size: 12)).foregroundStyle(.secondary); if !model.notificationPermission.isEmpty { Text(model.notificationPermission).font(.caption) } }; Spacer(); Button(T("Mitteilungen erlauben")) { Task { await model.requestNotifications() } } } }
            ForEach(model.workspace.rules) { rule in
                HStack(alignment: .center, spacing: 16) { Image(systemName: rule.conditions.isEmpty ? "bell" : "line.3.horizontal.decrease.circle").font(.system(size: 22)).foregroundStyle(Theme.blue); VStack(alignment: .leading, spacing: 6) { Text(rule.name).font(.system(size: 16, weight: .semibold)); Text((rule.shopID.flatMap { id in model.workspace.shops.first { $0.id == id }?.name } ?? T("Alle Shops")) + " · " + (rule.conditions.isEmpty ? T("Alle neuen Bestellungen") : "\(rule.conditions.count) " + T(rule.matchAll ? "Bedingungen, alle müssen passen" : "Bedingungen, eine muss passen"))).font(.system(size: 12)).foregroundStyle(.secondary) }; Spacer(); Toggle(T("Aktiv"), isOn: Binding(get: { rule.enabled }, set: { v in model.mutate { state in if let i = state.rules.firstIndex(where: { $0.id == rule.id }) { state.rules[i].enabled = v } } })).labelsHidden().toggleStyle(.switch).controlSize(.small); Button(T("Bearbeiten")) { editing = rule }; Button { model.mutate { $0.rules.removeAll { $0.id == rule.id } } } label: { Image(systemName: "trash") }.buttonStyle(.borderless).help(T("Regel löschen")) }.padding(.vertical, 15)
                Divider()
            }
            if model.workspace.rules.isEmpty { ContentUnavailableView(T("Deine erste Regel"), systemImage: "bell", description: Text(T("Alle Bestellungen oder nur bestimmte Beträge, Währungen, Status und Kundeneigenschaften."))).padding(.vertical, 35) }
            HStack { Button(T("Jetzt prüfen")) { Task { await model.pollOrders(); model.notice = T("Bestellungen geprüft.") } }.disabled(model.polling); Button(T("Testmitteilung senden")) { Task { await model.notify(title: "Shopdeck", body: T("Deine Bestellbenachrichtigungen sind bereit.")) } }; Spacer() }
        }.padding(30) }
        .sheet(isPresented: $adding) { RuleFormView(model: model, existing: nil) }
        .sheet(item: $editing) { RuleFormView(model: model, existing: $0) }
    }
}
struct RuleFormView: View {
    var model: AppModel
    let existing: OrderRule?
    @LocalState<String> private var name = ""
    @LocalState<UUID?> private var shopID: UUID?
    @LocalState<[OrderCondition]> private var conditions: [OrderCondition] = []
    @LocalState<Bool> private var matchAll = true
    @LocalState<String> private var result = ""
    @Environment(\.dismiss) private var dismiss
    private let fields = [("amountTotal", "Bestellwert"), ("shippingTotal", "Versandkosten"), ("currency.isoCode", "Währung"), ("stateMachineState.technicalName", "Bestellstatus"), ("orderNumber", "Bestellnummer"), ("orderCustomer.email", "Kunden E Mail")]
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(existing == nil ? T("Eine Regel für deine Bestellungen.") : T("Regel bearbeiten")).font(.title2.bold())
            TextField(T("Name der Regel"), text: $name).textFieldStyle(.roundedBorder)
            Picker(T("Shop"), selection: $shopID) { Text(T("Alle Shops")).tag(nil as UUID?); ForEach(model.workspace.shops) { Text($0.name).tag(Optional($0.id)) } }
            Picker(T("Verknüpfung"), selection: $matchAll) { Text(T("Alle Bedingungen")).tag(true); Text(T("Mindestens eine Bedingung")).tag(false) }
            if conditions.isEmpty { Text(T("Ohne Bedingungen gilt die Regel für alle neuen Bestellungen.")).font(.system(size: 12)).foregroundStyle(.secondary) }
            ScrollView { VStack(spacing: 12) {
                ForEach($conditions) { $condition in
                    HStack {
                        Picker("", selection: $condition.field) { ForEach(fields, id: \.0) { field, label in Text(T(label)).tag(field) } }.labelsHidden().frame(width: 165).onChange(of: condition.field) { _, field in condition.comparison = ["amountTotal", "shippingTotal"].contains(field) ? "gte" : "eq"; condition.value = field == "currency.isoCode" ? "EUR" : field == "stateMachineState.technicalName" ? "open" : ["amountTotal", "shippingTotal"].contains(field) ? "100" : "" }
                        Picker("", selection: $condition.comparison) { if ["amountTotal", "shippingTotal"].contains(condition.field) { Text("≥").tag("gte"); Text("≤").tag("lte") }; Text("=").tag("eq"); if !["amountTotal", "shippingTotal"].contains(condition.field) { Text(T("enthält")).tag("contains") } }.labelsHidden().frame(width: 105)
                        TextField(T("Wert"), text: $condition.value).textFieldStyle(.roundedBorder)
                        Button { conditions.removeAll { $0.id == condition.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).help(T("Bedingung entfernen"))
                    }
                }
            } }.frame(minHeight: 90, maxHeight: 210)
            Button(T("Bedingung hinzufügen")) { conditions.append(OrderCondition()) }
            Text(T("Währungswerte wie EUR, USD oder GBP. Statuswerte: open, in_progress, completed, cancelled. Beträge werden in der Währung der Bestellung verglichen.")).font(.system(size: 11)).foregroundStyle(.secondary)
            if !result.isEmpty { Text(result).font(.system(size: 12)).foregroundStyle(Theme.blue) }
            Divider()
            HStack { Button(T("Mit letzter Bestellung testen")) { Task { let shops = model.workspace.shops.filter { shopID == nil || $0.id == shopID }; var count = 0; for shop in shops { if let last = try? await model.client.search(shop, entity: "order", limit: 1).rows.first, OrderRule(name: name, shopID: shopID, conditions: conditions, matchAll: matchAll).matches(last, shopID: shop.id) { count += 1 } }; result = "\(count) " + T("aktuelle Bestellungen passen zur Regel.") } }; Spacer(); Button(T("Abbrechen")) { dismiss() }; Button(T("Speichern")) { var rule = existing ?? OrderRule(name: name); rule.name = name; rule.shopID = shopID; rule.conditions = conditions; rule.matchAll = matchAll; model.mutate { state in if let i = state.rules.firstIndex(where: { $0.id == rule.id }) { state.rules[i] = rule } else { state.rules.append(rule) } }; dismiss() }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || conditions.contains { $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (["amountTotal", "shippingTotal"].contains($0.field) && Double($0.value.replacingOccurrences(of: ",", with: ".")) == nil) }) }
        }.padding(28).frame(width: 700).onAppear { if let rule = existing { name = rule.name; shopID = rule.shopID; conditions = rule.conditions; matchAll = rule.matchAll } }
    }
}
