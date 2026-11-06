import SwiftUI
import ShopdeckCore

struct ProductHistoryView: View {
    @Bindable var model: AppModel
    @LocalState<ProductChangeRecord?> private var undoing: ProductChangeRecord?
    @LocalState<Bool> private var onlyOpen = false
    @LocalState<String> private var search=""
    @LocalState<Int> private var visible=100
    @LocalState<String?> private var undoBatch:String?
    private var entries: [ProductChangeRecord] {
        model.journal.changes.filter { (model.selectedShopID == nil || $0.shopID == model.selectedShopID) && (search.isEmpty || ($0.productName+" "+$0.shopName+" "+$0.origin).localizedCaseInsensitiveContains(search)) && (!onlyOpen || [.applying, .uncertain].contains($0.status)) }.reversed()
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) { PageTitle(title: T("Jede Änderung nachvollziehbar."), subtitle: T("Vorher und Nachher bleiben erhalten. Du kannst bestätigte Änderungen gezielt zurücknehmen.")); Spacer(); Toggle(T("Nur offene Prüfungen"), isOn: $onlyOpen).toggleStyle(.button) }
                HStack{Image(systemName:"magnifyingglass").foregroundStyle(.secondary);TextField(T("Im Verlauf suchen"),text:$search).textFieldStyle(.plain);Text("\(entries.count) "+T("Produkte")).font(.caption).foregroundStyle(.secondary)}.padding(12).background(Theme.surface,in:RoundedRectangle(cornerRadius:8))
                OperationHistorySection(model:model,search:search,onlyOpen:onlyOpen)
                if entries.isEmpty && model.adminQueue.proposals.isEmpty && model.automationQueue.operations.isEmpty { ContentUnavailableView(T("Noch keine Änderungen"), systemImage: "arrow.uturn.backward.circle", description: Text(T("Produkteditor, Sammelbearbeitung und freigegebene KI Vorschläge schreiben ab jetzt in diesen Verlauf."))).frame(maxWidth: .infinity).padding(.vertical, 50) }
                ForEach(Array(entries.prefix(visible))) { entry in
                    VStack(alignment: .leading, spacing: 17) {
                        HStack(spacing: 12) {
                            Image(systemName: entry.undoOfID == nil ? "square.and.pencil" : "arrow.uturn.backward").font(.system(size: 20)).foregroundStyle(Theme.blue)
                            VStack(alignment: .leading, spacing: 5) { Text(entry.productName).font(.system(size: 17, weight: .semibold)); Text(entry.shopName + (entry.isDemo ? " · " + T("Demo") : "") + " · " + originTitle(entry.origin)).font(.system(size: 11)).foregroundStyle(.secondary) }
                            Spacer()
                            StatusPill(text: statusTitle(entry.status), color: entry.status == .applied ? .green : entry.status == .undone ? .secondary : .orange)
                        }
                        ForEach(entry.after.keys.sorted(), id: \.self) { key in
                            HStack(alignment: .top, spacing: 16) { Text(T(key)).foregroundStyle(.secondary).frame(width: 95, alignment: .leading); Text(productValue(entry.before[key] ?? .null)).foregroundStyle(.secondary).lineLimit(5).frame(maxWidth: .infinity, alignment: .leading); Image(systemName: "arrow.right").foregroundStyle(Theme.blue); Text(productValue(entry.after[key] ?? .null)).lineLimit(5).frame(maxWidth: .infinity, alignment: .leading) }.font(.system(size: 13)).textSelection(.enabled)
                        }
                        if let error = entry.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
                        HStack {
                            Text(localizedDate(entry.createdAt,date:.abbreviated,time:.shortened)).font(.system(size: 10)).foregroundStyle(.secondary)
                            Spacer()
                            if [.applying, .uncertain].contains(entry.status) { Button(T("Mit Shop abgleichen")) { Task { await model.reconcileChange(entry) } }.disabled(model.isChangingProducts) }
                            if entry.status == .applied && entry.undoOfID==nil && entry.origin.hasPrefix("ai-batch:"){Button(T("Charge zurücknehmen")){undoBatch=entry.origin}.disabled(model.isChangingProducts)}
                            if entry.status == .applied && entry.undoOfID == nil { Button { undoing = entry } label: { Label(T("Rückgängig machen"), systemImage: "arrow.uturn.backward") }.disabled(model.isChangingProducts) }
                        }
                    }.padding(24).background(Theme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
                }
                if entries.count>visible{Button(T("Weitere Einträge laden")){visible+=100}}
            }.padding(30)
        }
        .confirmationDialog(T("Charge zurücknehmen?"),isPresented:Binding(get:{undoBatch != nil},set:{if !$0{undoBatch=nil}})){Button(T("Bestätigte Änderungen zurücknehmen")){if let batch=undoBatch{Task{await model.undoBatch(batch)}};undoBatch=nil}}message:{Text(T("Die Charge wird in umgekehrter Reihenfolge zurückgenommen. Bei einem Konflikt hält Shopdeck an und schützt neuere Werte."))}
        .confirmationDialog(T("Änderung rückgängig machen?"), isPresented: Binding(get: { undoing != nil }, set: { if !$0 { undoing = nil } })) {
            Button(T("Ursprüngliche Werte wiederherstellen")) { if let entry = undoing { Task { await model.undoChange(entry) } }; undoing = nil }
        } message: { Text(T("Shopdeck prüft zuerst die aktuellen Werte. Neuere Änderungen werden nicht überschrieben.")) }
    }
    private func originTitle(_ origin: String) -> String { if origin.hasPrefix("ai-batch:"){return T("KI Sammeländerung")};switch origin { case "bulk": return T("Gemeinsam bearbeitet"); case "ai": return T("KI Vorschlag"); case "undo": return T("Rücknahme"); default: return T("Produkteditor") } }
    private func statusTitle(_ status: ProductChangeStatus) -> String { switch status { case .applied: return T("Übernommen"); case .applying: return T("Wird übernommen"); case .uncertain: return T("Zu prüfen"); case .failed: return T("Nicht übernommen"); case .undone: return T("Zurückgenommen") } }
}
