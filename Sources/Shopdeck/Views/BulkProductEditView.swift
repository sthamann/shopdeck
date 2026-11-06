import SwiftUI
import ShopdeckCore

struct BulkProductEditView: View {
    var model: AppModel
    let records: [ShopRecord]
    @Environment(\.dismiss) private var dismiss
    @LocalState<Bool> private var changeStock = true
    @LocalState<String> private var stock = "10"
    @LocalState<BulkStockMode> private var stockMode = .adjust
    @LocalState<String> private var activeMode = "keep"
    @LocalState<[BulkProductPlan]> private var plans: [BulkProductPlan] = []
    @LocalState<[String: String]> private var preparationErrors: [String: String] = [:]
    @LocalState<[String: String]> private var outcomes: [String: String] = [:]
    @LocalState<Bool> private var preparing = false
    @LocalState<Bool> private var applying = false
    @LocalState<Bool> private var finished = false
    @LocalState<Bool> private var stopRequested = false
    @LocalState<Int> private var completed = 0
    @LocalState<Bool> private var hasPreview = false
    private var validDraft: Bool { (!changeStock || Int(stock) != nil) && (changeStock || activeMode != "keep") }
    private var changedPlans: [BulkProductPlan] { plans.filter { !$0.after.isEmpty } }
    private var issueCount: Int { Set(outcomes.filter { $0.value != "applied" && $0.value != "unchanged" }.keys).union(preparationErrors.keys).count }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "square.stack.3d.up").font(.system(size: 30)).foregroundStyle(Theme.blue)
                VStack(alignment: .leading, spacing: 7) { Text(T("Ein Durchgang. Mehrere Produkte.")).font(.system(size: 25, weight: .bold)); Text("\(records.count) " + T("ausgewählte Produkte") + " · \(Set(records.map { $0.shop.id }).count) " + T("Shops")).font(.system(size: 12)).foregroundStyle(.secondary) }
                Spacer()
                if records.allSatisfy({ $0.shop.isDemo }) { StatusPill(text: T("Demodaten"), color: .orange) }
            }
            if !hasPreview {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        Toggle(T("Bestand ändern"), isOn: $changeStock).toggleStyle(.checkbox)
                        Picker(T("Aktion"), selection: $stockMode) { Text(T("Um Betrag ändern")).tag(BulkStockMode.adjust); Text(T("Auf Wert setzen")).tag(BulkStockMode.set) }.labelsHidden().frame(width: 200).disabled(!changeStock)
                        TextField(T("Wert"), text: $stock).textFieldStyle(.roundedBorder).frame(width: 95).disabled(!changeStock)
                    }
                    Picker(T("Aktivstatus"), selection: $activeMode) { Text(T("Beibehalten")).tag("keep"); Text(T("Alle aktivieren")).tag("active"); Text(T("Alle deaktivieren")).tag("inactive") }.frame(maxWidth: 430)
                    Text(T("Ein negativer Betrag verringert den Bestand. Vor dem Schreiben liest Shopdeck alle betroffenen Produkte neu und zeigt die konkreten Änderungen.")).font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(3)
                }.padding(22).background(Theme.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            }
            if preparing { ProgressView(T("Vorschau wird aus dem Shop geladen …"), value: Double(completed), total: Double(max(records.count, 1))) }
            if applying { ProgressView(T("Änderungen werden übernommen …"), value: Double(completed), total: Double(max(changedPlans.count, 1))) }
            if finished {
                HStack(spacing: 18) {
                    Label("\(outcomes.values.filter { $0 == "applied" }.count) " + T("übernommen"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("\(issueCount) " + T("zu prüfen")).foregroundStyle(.orange)
                    Spacer()
                    Button(T("Änderungsverlauf öffnen")) { model.destination = .history; dismiss() }
                }.font(.system(size: 13))
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(records) { record in
                        let plan = plans.first { $0.shop.id == record.shop.id && $0.productID == record.data["id"].string }
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 12) {
                                ShopIcon(shop: record.shop, size: 28)
                                VStack(alignment: .leading, spacing: 4) { Text(plan?.productName ?? record.data["name"].string ?? "–").font(.system(size: 13, weight: .semibold)); Text(record.shop.name).font(.system(size: 11)).foregroundStyle(.secondary) }
                                Spacer()
                                if let outcome = outcomes[record.id] { StatusPill(text: outcomeTitle(outcome), color: outcome == "applied" ? .green : outcome == "unchanged" ? .secondary : .orange) }
                                else if let plan, plan.after.isEmpty { Text(T("Unverändert")).font(.caption).foregroundStyle(.secondary) }
                            }
                            if let error = preparationErrors[record.id] { Text(error).font(.caption).foregroundStyle(.orange) }
                            if let plan { ForEach(plan.after.keys.sorted(), id: \.self) { field in
                                HStack { Text(T(field)).frame(width: 100, alignment: .leading).foregroundStyle(.secondary); Text(productValue(plan.before[field] ?? .null)).foregroundStyle(.secondary); Image(systemName: "arrow.right").font(.system(size: 10)); Text(productValue(plan.after[field] ?? .null)).fontWeight(.semibold); Spacer() }.font(.system(size: 12)).padding(.leading, 40)
                            } }
                        }.padding(.vertical, 15)
                        Divider()
                    }
                }
            }.frame(minHeight: 150, maxHeight: .infinity)
            Text(T("Jedes erfolgreich geänderte Produkt erhält einen eigenen Eintrag zum Rückgängigmachen. Produkte mit Fehlern bleiben einzeln erkennbar.")).font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Button(applying ? T("Nach diesem Produkt stoppen") : finished ? T("Schließen") : T("Abbrechen")) { if applying { stopRequested = true } else { dismiss() } }.disabled(preparing || (applying && stopRequested))
                Spacer()
                if hasPreview && !finished && !applying { Button(T("Einstellungen anpassen")) { hasPreview = false; plans = []; preparationErrors = [:] } }
                if !hasPreview { Button(T("Vorschau laden")) { Task { await prepare() } }.buttonStyle(.borderedProminent).disabled(!validDraft || preparing) }
                else if !finished { Button("\(changedPlans.count) " + T("Produkte jetzt ändern")) { Task { await apply() } }.buttonStyle(.borderedProminent).disabled(applying || changedPlans.isEmpty) }
            }
        }.padding(28).frame(width: 760, height: 690).interactiveDismissDisabled(applying || preparing)
    }
    private func prepare() async {
        preparing = true; completed = 0; preparationErrors = [:]; plans = []; defer { preparing = false }
        let draft = BulkProductDraft(stock: changeStock ? Int(stock) : nil, stockMode: stockMode, active: activeMode == "keep" ? nil : activeMode == "active")
        for record in records {
            do { plans.append(try await model.changeService.preview(record.shop, id: record.data["id"].string ?? "", draft: draft)) }
            catch { preparationErrors[record.id] = error.localizedDescription }
            completed += 1
        }
        hasPreview = true
    }
    private func apply() async {
        applying = true; model.isChangingProducts = true; completed = 0
        defer { applying = false; model.isChangingProducts = false; finished = true; model.reload() }
        let operation = UUID()
        for plan in plans where plan.after.isEmpty { outcomes[plan.shop.id.uuidString + plan.productID] = "unchanged" }
        for plan in changedPlans {
            if stopRequested { break }
            let key = plan.shop.id.uuidString + plan.productID
            do {
                let entry = try await model.changeService.apply(plan.shop, id: plan.productID, changes: plan.after, origin: "bulk", operationID: operation, expectedBefore: plan.before)
                outcomes[key] = entry?.status == .applied ? "applied" : entry == nil ? "unchanged" : "uncertain"
            } catch { outcomes[key] = "failed"; preparationErrors[key] = error.localizedDescription }
            completed += 1
        }
        for plan in changedPlans { let key = plan.shop.id.uuidString + plan.productID; if outcomes[key] == nil { outcomes[key] = "not_run" } }
        await model.refresh()
    }
    private func outcomeTitle(_ key: String) -> String { switch key { case "applied": return T("Übernommen"); case "unchanged": return T("Unverändert"); case "uncertain": return T("Zu prüfen"); case "not_run": return T("Nicht ausgeführt"); default: return T("Fehlgeschlagen") } }
}

func productValue(_ value: JSONValue) -> String {
    switch value { case .null: return T("Vererbt oder leer"); case .string(let s): return s.isEmpty ? T("Leer") : s; case .number(let n): return n.formatted(.number.locale(Locale(identifier:Language.current))); case .bool(let b): return b ? T("Aktiv") : T("Inaktiv"); default: return value.pretty }
}
