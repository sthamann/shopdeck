import SwiftUI
import Observation
import ShopdeckCore

private struct ShopWorkspaceActionKey: EnvironmentKey { static let defaultValue: (Shop?, Bool) -> Void = { _,_ in } }
extension EnvironmentValues { var openShopWorkspace: (Shop?, Bool) -> Void { get { self[ShopWorkspaceActionKey.self] } set { self[ShopWorkspaceActionKey.self] = newValue } } }
@MainActor @Observable final class ShopWorkspace: Identifiable {
    let id: UUID
    let model: AppModel
    init(model: AppModel, id: UUID = UUID()) { self.model = model; self.id = id }
    var title: String { model.selectedShop.map { $0.name + " · " + model.destination.title } ?? model.destination.title }
}
struct WorkspaceShell: View {
    var root: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @AppStorage("restoreWorkspaceOnLaunch") private var restoreOnLaunch = true
    @LocalState<Bool> private var onboarding = false
    @LocalState<Bool> private var exploreDemoAfterOnboarding = false
    @LocalState<[ShopWorkspace]> private var tabs: [ShopWorkspace] = []
    @LocalState<UUID?> private var selected: UUID? = nil
    @LocalState<UUID?> private var secondary: UUID? = nil
    @LocalState<[DesktopTab]> private var closed: [DesktopTab] = []
    @LocalState<DesktopState> private var desktop = DesktopState()
    @LocalState<Bool> private var initialized = false
    @LocalState<Bool> private var storageFailed = false
    @LocalState<UUID> private var presentationID = UUID()
    @LocalState<Bool> private var naming = false
    @LocalState<String> private var name = ""
    private var active: ShopWorkspace? { tabs.first { $0.id == selected } ?? tabs.first }
    private var session: DesktopSession { .init(tabs: tabs.map { $0.model.desktopTab(id: $0.id) }, selected: active?.id, secondary: secondary) }
    var body: some View {
        VStack(spacing: 0) {
            if tabs.count > 1 {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 4) {
                            ForEach(tabs) { tab in tabButton(tab).id(tab.id) }
                        }.padding(.horizontal, 14).padding(.vertical, 5)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: selected) { _, id in
                        if let id { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { proxy.scrollTo(id) } }
                    }
                }
                Divider()
            }
            HSplitView {
                if let active { ContentView(model: active.model).id(active.id.uuidString + presentationID.uuidString).frame(minWidth: secondary == nil ? 900 : 650) }
                if let split = tabs.first(where: { $0.id == secondary }), split.id != active?.id { ContentView(model: split.model, showSidebar: false).id(split.id.uuidString + presentationID.uuidString).frame(minWidth: 480) }
            }
        }
            .toolbar { workspaceToolbar }
            .environment(\.openShopWorkspace, { shop, split in open(shop, split: split) })
            .sheet(isPresented: $onboarding, onDismiss: loadOnboardingDemo) {
                OnboardingView(model: root) { openAI in
                    onboardingCompleted = true
                    onboarding = false
                    if openAI { active?.model.destination = .ai }
                } exploreDemo: {
                    exploreDemoAfterOnboarding = true
                    onboardingCompleted = true
                    onboarding = false
                }
            }
            .sheet(isPresented: $naming) { savePresetSheet }
            .onAppear { initialize() }
            .task(id: session) {
                guard initialized, !storageFailed else { return }
                do { try await Task.sleep(for: .milliseconds(250)); try Task.checkCancellation(); persist() } catch { }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in persist() }
            .onReceive(NotificationCenter.default.publisher(for: .shopdeckAction)) { event in handleAction(event.object as? String) }
            .onReceive(NotificationCenter.default.publisher(for: .shopdeckOpenFollowUp)) { event in openNotification(event.object as? String) }
            .onOpenURL { url in if url.scheme == "shopdeck" { active?.model.destination = .overview; Task { await active?.model.refresh() } } }
            .task(id: [active?.id, secondary]) { for tab in tabs where tab.id == active?.id || tab.id == secondary { if tab.model.snapshots.isEmpty { await tab.model.refresh() } } }
            .task { while !Task.isCancelled { for tab in tabs { tab.model.reload(); if Date().timeIntervalSince(tab.model.clock) > 60 { tab.model.clock = Date() } }; try? await Task.sleep(for: .seconds(3)) } }
            .background(Button("") { cycle(1) }.keyboardShortcut("]", modifiers: [.command, .shift]).hidden())
            .background(Button("") { cycle(-1) }.keyboardShortcut("[", modifiers: [.command, .shift]).hidden())
            .background(Button("") { if let active, tabs.count > 1 { close(active.id) } }.keyboardShortcut("w").disabled(tabs.count < 2).hidden())
    }
    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if let active {
                Button { active.model.showingCommandPalette = true } label: {
                    Label(T("Schnellsuche"), systemImage: "magnifyingglass")
                }.help(T("Schnellsuche") + " · ⌘K")
                BookmarkMenu(model: active.model)
            }
            workspaceMenu
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button { open(nil, split: false) } label: {
                Label(T("Neuer Tab"), systemImage: "plus.square")
            }.help(T("Neuer Tab") + " · ⌘T")
            Button { toggleSplit() } label: {
                Label(T("Nebeneinander anzeigen"), systemImage: secondary == nil ? "rectangle.split.2x1" : "rectangle.split.2x1.fill")
            }
            .help(T("Nebeneinander anzeigen"))
            .accessibilityAddTraits(secondary == nil ? [] : .isSelected)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if let active {
                Button { Task { await active.model.refresh() } } label: {
                    if active.model.isRefreshing {
                        ProgressView().controlSize(.small).frame(width: 18, height: 18)
                    } else {
                        Label(T("Aktualisieren"), systemImage: "arrow.clockwise")
                    }
                }.help(T("Aktualisieren")).disabled(active.model.isRefreshing)
                Button { active.model.showingAddShop = true } label: {
                    Label(T("Shop hinzufügen"), systemImage: "plus")
                }.help(T("Shop hinzufügen"))
            }
        }
    }

    private func tabButton(_ tab: ShopWorkspace) -> some View {
        let isActive = active?.id == tab.id
        return HStack(spacing: 2) {
            Button {
                selected = tab.id
                if secondary == tab.id { secondary = nil }
            } label: {
                Label(tab.title, systemImage: tab.model.destination.icon)
                    .lineLimit(1)
                    .padding(.leading, 9)
                    .padding(.trailing, 5)
                    .frame(minHeight: 29)
                    .contentShape(Rectangle())
            }
            .buttonStyle(WorkspaceRowStyle())
            .accessibilityAddTraits(isActive ? .isSelected : [])
            .help(tab.title)
            Button { close(tab.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 25, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(WorkspaceRowStyle())
            .accessibilityLabel(T("Tab schließen") + " · " + tab.title)
            .help(T("Tab schließen"))
        }
        .font(.system(size: 12, weight: isActive ? .semibold : .medium))
        .foregroundStyle(isActive ? Color.primary : Color.secondary)
        .padding(2)
        .background(isActive ? Color.primary.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isActive)
        .contextMenu {
            Button(T("Tab duplizieren")) { duplicate(tab) }
            Button(T("Nebeneinander anzeigen")) { if !isActive { secondary = tab.id } }.disabled(isActive)
            Button(T("Andere Tabs schließen")) { tabs = [tab]; selected = tab.id; secondary = nil }
            Button(T("Tab schließen")) { close(tab.id) }
        }
    }
    private var workspaceMenu: some View {
        Menu {
            Button(T("Arbeitsplatz speichern …")) { name = ""; naming = true }
            if !desktop.presets.isEmpty {
                Divider()
                ForEach(desktop.presets) { preset in Button(preset.name) { restore(preset.session) } }
                Menu(T("Arbeitsplatz entfernen")) { ForEach(desktop.presets) { preset in Button(preset.name) { changeDesktop { $0.presets.removeAll { $0.id == preset.id } } } } }
            }
            Divider()
            Button(T("Geschlossenen Tab wieder öffnen")) { reopen() }.disabled(closed.isEmpty)
            Toggle(T("Tabs beim Start wiederherstellen"), isOn: $restoreOnLaunch)
        } label: { Label(T("Arbeitsplätze"), systemImage: "rectangle.3.group") }.help(T("Arbeitsplätze und Tabs"))
    }
    private var savePresetSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(T("Arbeitsplatz speichern")).font(.title2.bold())
            Text(T("Tabs, Shopauswahl, Suche, Filter und Sortierung gemeinsam wieder öffnen.")).foregroundStyle(.secondary)
            TextField(T("Name"), text: $name).textFieldStyle(.roundedBorder)
            Text("\(tabs.count) " + T("Tabs")).font(.caption).foregroundStyle(.secondary)
            HStack { Button(T("Abbrechen")) { naming = false }.keyboardShortcut(.cancelAction); Spacer(); Button(T("Speichern")) { savePreset() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        }.padding(26).frame(width: 460)
    }
    private func loadOnboardingDemo() {
        guard exploreDemoAfterOnboarding else { return }
        exploreDemoAfterOnboarding = false
        Task {
            await root.addDemo()
            if root.workspace.shops.isEmpty { onboardingCompleted = false }
        }
    }
    private func initialize() {
        guard !initialized else { return }
        do { desktop = try root.store.readDesktopState() } catch { storageFailed = true; root.notice = T("Der letzte Arbeitsplatz konnte nicht geladen werden. Deine Shops sind weiterhin verfügbar.") }
        if restoreOnLaunch, !desktop.lastSession.tabs.isEmpty { restore(desktop.lastSession) }
        else { let tab = ShopWorkspace(model: root); tabs = [tab]; selected = tab.id }
        initialized = true
        if root.workspace.shops.isEmpty && !onboardingCompleted { onboarding = true }
        openNotification(UserDefaults.standard.string(forKey: "pendingFollowUpToOpen"))
    }
    private func restore(_ value: DesktopSession) {
        let value = value.validated(shopIDs: Set(root.workspace.shops.map(\.id)))
        guard !value.tabs.isEmpty else { return }
        tabs = value.tabs.enumerated().map { index, snapshot in
            let model = index == 0 ? root : AppModel(); model.restoreDesktopTab(snapshot)
            return ShopWorkspace(model: model, id: snapshot.id)
        }
        selected = value.selected; secondary = value.secondary; presentationID = UUID()
    }
    private func persist() {
        guard initialized, !storageFailed, !tabs.isEmpty else { return }
        changeDesktop { $0.lastSession = session }
    }
    private func changeDesktop(_ change: (inout DesktopState) -> Void) {
        do { try root.store.updateDesktopState(change); desktop = try root.store.readDesktopState() }
        catch { storageFailed = true; root.notice = T("Der Arbeitsplatz konnte nicht gespeichert werden.") + " " + error.localizedDescription }
    }
    private func savePreset() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let current = session
        changeDesktop { state in
            if let index = state.presets.firstIndex(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) { state.presets[index].session = current }
            else { state.presets.append(.init(name: clean, session: current)) }
        }
        if !storageFailed { naming = false; root.notice = T("Arbeitsplatz gespeichert") }
    }
    private func open(_ shop: Shop?, split: Bool) {
        let model = AppModel(); model.selectedShopID = shop?.id; model.destination = shop == nil ? .overview : .admin
        let tab = ShopWorkspace(model: model); tabs.append(tab)
        if split { secondary = tab.id } else { selected = tab.id }
        Task { await model.refresh() }
    }
    private func duplicate(_ tab: ShopWorkspace) {
        var snapshot = tab.model.desktopTab(id: UUID()); snapshot.id = UUID()
        let model = AppModel(); model.restoreDesktopTab(snapshot)
        let next = ShopWorkspace(model: model, id: snapshot.id); tabs.append(next); selected = next.id
        Task { await model.refresh() }
    }
    private func close(_ id: UUID) {
        guard tabs.count > 1, let tab = tabs.first(where: { $0.id == id }) else { return }
        closed = Array((closed + [tab.model.desktopTab(id: tab.id)]).suffix(10)); tabs.removeAll { $0.id == id }
        if secondary == id { secondary = nil }; if selected == id { selected = tabs.first?.id }
    }
    private func reopen() {
        guard var snapshot = closed.popLast() else { return }; if tabs.contains(where: { $0.id == snapshot.id }) { snapshot.id = UUID() }
        let model = AppModel(); model.restoreDesktopTab(snapshot); let tab = ShopWorkspace(model: model, id: snapshot.id); tabs.append(tab); selected = tab.id
        Task { await model.refresh() }
    }
    private func toggleSplit() { if secondary != nil { secondary = nil } else if let other = tabs.first(where: { $0.id != active?.id }) { secondary = other.id } else { open(active?.model.selectedShop, split: true) } }
    private func cycle(_ offset: Int) { guard let active, let index = tabs.firstIndex(where: { $0.id == active.id }), !tabs.isEmpty else { return }; selected = tabs[(index + offset + tabs.count) % tabs.count].id; if secondary == selected { secondary = nil } }
    private func handleAction(_ action: String?) {
        if action == "onboard" { onboarding = true; return }
        guard let model = active?.model else { return }
        switch action {
        case "newTab": open(nil, split: false)
        case "reopenTab": reopen()
        case "split": toggleSplit()
        case "search": model.showingCommandPalette = true
        case "add": model.showingAddShop = true
        case "refresh": Task { await model.refresh() }
        case "ai": model.destination = .ai
        case "dashboard": model.destination = .overview
        default: break
        }
    }
    private func openNotification(_ id: String?) {
        guard let id, let uuid = UUID(uuidString: id) else { return }
        guard let item = root.followUps.first(where: { $0.id == uuid }) else { return }
        UserDefaults.standard.removeObject(forKey: "pendingFollowUpToOpen")
        Task { @MainActor in await Task.yield(); active?.model.openFollowUp(item) }
    }
}
