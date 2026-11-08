import SwiftUI
import ShopdeckCore

struct MerchantFocusView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(MerchantFocusPreferences.enabledKey) private var enabled = true
    @AppStorage(MerchantFocusPreferences.hiddenChecksKey) private var hiddenChecks = ""
    @AppStorage("focusShowFollowUps") private var showFollowUps = true
    @AppStorage("focusStockThreshold") private var stock = 10
    @AppStorage("focusOverdueHours") private var hours = 48
    @LocalState<Bool> private var settings = false
    @LocalState<Bool> private var expanded = true
    private var checks: [MerchantFocus] { MerchantFocusPreferences.checks(excluding: hiddenChecks) }
    private var queryKey: String { model.merchantFocusKey(checks: checks, stockThreshold: stock, overdueHours: hours) }
    private var current: Bool { model.focusSnapshot.key == queryKey }
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { expanded.toggle() } } label: { Label(T("Jetzt angehen"), systemImage: expanded ? "chevron.down" : "chevron.right").font(.system(size: 17, weight: .semibold)) }.buttonStyle(.plain)
                if model.loadingFocus { ProgressView().controlSize(.small) }
                Spacer()
                if showFollowUps, model.dueFollowUpCount > 0 {
                    Button { model.selectedShopID = nil; model.destination = .followups } label: { Label("\(model.dueFollowUpCount) " + T("fällige Wiedervorlagen"), systemImage: "bookmark.circle") }.buttonStyle(.borderless)
                }
                Button { settings.toggle() } label: {
                    Label(T("Arbeitsvorrat konfigurieren"), systemImage: "slider.horizontal.3").labelStyle(.iconOnly)
                }.buttonStyle(.borderless).help(T("Arbeitsvorrat konfigurieren"))
                    .popover(isPresented: $settings) { preferences }
                Button { Task { await model.loadMerchantFocus(force: true) } } label: {
                    Label(T("Arbeitsvorrat aktualisieren"), systemImage: "arrow.clockwise").labelStyle(.iconOnly)
                }.buttonStyle(.borderless).disabled(model.loadingFocus || checks.isEmpty).help(T("Arbeitsvorrat aktualisieren"))
            }
            if expanded && checks.isEmpty {
                Text(T("Keine Prüfungen ausgewählt.")).font(.caption).foregroundStyle(.secondary)
            } else if expanded {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 32)], spacing: 0) {
                    ForEach(checks) { focus in
                        Button { model.openFocus(focus) } label: { focusRow(focus) }
                            .buttonStyle(WorkspaceRowStyle()).help(T("Betroffene Datensätze öffnen"))
                    }
                }
                HStack {
                    Text(T("Live im Shop gezählt. Ein Klick öffnet die passenden Datensätze.")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    if let loaded = model.focusSnapshot.loadedAt, current { Text(localizedDate(loaded, date: .omitted, time: .shortened)).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit() }
                }
            }
        }.padding(15).background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
            .task(id: queryKey) { await model.loadMerchantFocus() }
            .onDisappear { model.stopMerchantFocusLoading() }
    }
    private var preferences: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(T("Arbeitsvorrat konfigurieren")).font(.headline)
            VStack(alignment: .leading, spacing: 5) {
                Toggle(T("Arbeitsvorrat anzeigen"), isOn: $enabled)
                Text(T("Den Bereich kannst du unter Einstellungen → Dashboard wieder einschalten."))
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                ForEach(MerchantFocus.allCases) { focus in
                    Toggle(T(focus.title), isOn: checkBinding(focus))
                    if focus == .overdueOrders && checks.contains(focus) {
                        Stepper(T("Offen seit mindestens Stunden") + " \(hours)", value: $hours, in: 1...8760, step: 12)
                            .font(.callout).padding(.leading, 22)
                    }
                    if focus == .lowStock && checks.contains(focus) {
                        Stepper(T("Nachbestellen bei Bestand bis") + " \(stock)", value: $stock, in: 1...10000)
                            .font(.callout).padding(.leading, 22)
                    }
                }
            }
            Divider()
            Toggle(T("Fällige Wiedervorlagen anzeigen"), isOn: $showFollowUps)
        }.toggleStyle(.checkbox).padding(20).frame(width: 385)
    }
    private func checkBinding(_ focus: MerchantFocus) -> Binding<Bool> {
        Binding {
            checks.contains(focus)
        } set: { visible in
            var hidden = Set(MerchantFocus.allCases.filter { !checks.contains($0) })
            if visible { hidden.remove(focus) } else { hidden.insert(focus) }
            hiddenChecks = MerchantFocus.allCases.filter { hidden.contains($0) }.map(\.rawValue).joined(separator: ",")
        }
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
        }.padding(.vertical, 7).contentShape(Rectangle()).overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) }
    }
}
