import SwiftUI
import ShopdeckCore

struct MerchantFocusView: View {
    @Bindable var model: AppModel
    @AppStorage("focusStockThreshold") private var stock = 10
    @AppStorage("focusOverdueHours") private var hours = 48
    @LocalState<Bool> private var settings = false
    @LocalState<Bool> private var expanded = true
    private var current: Bool { model.focusSnapshot.key == model.merchantFocusKey }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Button { expanded.toggle() } label: { Label(T("Jetzt angehen"), systemImage: expanded ? "chevron.down" : "chevron.right").font(.system(size: 17, weight: .semibold)) }.buttonStyle(.plain)
                if model.loadingFocus { ProgressView().controlSize(.small) }
                Spacer()
                if model.dueFollowUpCount > 0 {
                    Button { model.selectedShopID = nil; model.destination = .followups } label: { Label("\(model.dueFollowUpCount) " + T("fällige Wiedervorlagen"), systemImage: "bookmark.circle") }.buttonStyle(.borderless)
                }
                Button { settings.toggle() } label: { Image(systemName: "slider.horizontal.3") }.buttonStyle(.borderless).help(T("Arbeitsvorrat konfigurieren"))
                    .popover(isPresented: $settings) {
                        VStack(alignment: .leading, spacing: 18) {
                            Text(T("Arbeitsvorrat konfigurieren")).font(.headline)
                            Stepper(T("Nachbestellen bei Bestand bis") + " \(stock)", value: $stock, in: 1...10000)
                            Stepper(T("Offen seit mindestens Stunden") + " \(hours)", value: $hours, in: 1...8760, step: 12)
                            Text(T("Produktinhalte werden nur bei aktiven Hauptprodukten geprüft. Varianten erben Inhalte.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.padding(22).frame(width: 355)
                    }
                Button { Task { await model.loadMerchantFocus(force: true) } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless).disabled(model.loadingFocus).help(T("Arbeitsvorrat aktualisieren"))
            }
            if expanded {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 32)], spacing: 0) {
                    ForEach(MerchantFocus.allCases) { focus in
                        Button { model.openFocus(focus) } label: { focusRow(focus) }
                            .buttonStyle(.plain).help(T("Betroffene Datensätze öffnen"))
                    }
                }
                HStack {
                    Text(T("Live im Shop gezählt. Ein Klick öffnet die passenden Datensätze.")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    if let loaded = model.focusSnapshot.loadedAt, current { Text(localizedDate(loaded, date: .omitted, time: .shortened)).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit() }
                }
            }
        }.padding(20).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .task(id: model.merchantFocusKey) { await model.loadMerchantFocus() }
    }
    private func focusRow(_ focus: MerchantFocus) -> some View {
        let errors = current ? model.focusSnapshot.failures[focus] ?? [] : []
        let value = current && model.focusSnapshot.loadedAt != nil ? model.focusSnapshot.counts[focus, default: 0] : nil
        return HStack(spacing: 12) {
            Image(systemName: focus.icon).font(.system(size: 16)).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(T(focus.title)).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if !errors.isEmpty { Text(T("Nicht alle Shops erreichbar")).font(.system(size: 11)).foregroundStyle(.orange).help(errors.joined(separator: "\n")) }
            }
            Spacer(minLength: 6)
            Text(!errors.isEmpty ? "–" : value.map(String.init) ?? "…").font(.system(size: 21, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(value != nil && value! > 0 && errors.isEmpty ? Theme.blue : Color.secondary)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
        }.padding(.vertical, 11).contentShape(Rectangle()).overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) }
    }
}
