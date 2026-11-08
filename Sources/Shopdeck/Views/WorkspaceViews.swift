import SwiftUI
import MarkdownUI
import ShopdeckCore

struct ChangesView: View {
    @Bindable var model: AppModel
    @LocalState<ChangeProposal?> private var confirming: ChangeProposal?
    @LocalState<JSONValue?> private var current: JSONValue?
    @LocalState<Bool> private var busy = false
    @LocalState<Bool> private var bulkReview=false
    var body: some View {
        ScrollView { LazyVStack(alignment: .leading, spacing: 24) {
            HStack{PageTitle(title: T("Du hast das letzte Wort."), subtitle: T("Prüfe KI Vorschläge und übernimm Änderungen gezielt in deinen Shop."));Spacer();Button(T("Alle übernehmen …")){bulkReview=true}.buttonStyle(.borderedProminent).disabled(scopedPending==0)}
            if model.selectedShopID != nil,model.pendingCount>scopedPending {HStack{Text("\(model.pendingCount-scopedPending) "+T("offene Änderungen in anderen Shops"));Spacer();Button(T("Alle Änderungen anzeigen")){model.selectedShopID=nil}}.font(.callout).padding(13).background(Theme.blue.opacity(0.08),in:RoundedRectangle(cornerRadius:9))}
            AutomationReviewSection(model:model)
            AdminAPIReviewSection(model:model)
            let proposals = model.workspace.proposals.filter { model.selectedShopID == nil || $0.shopID == model.selectedShopID }.reversed()
            if proposals.isEmpty && model.automationQueue.operations.filter({model.selectedShopID==nil || $0.shopID==model.selectedShopID}).isEmpty && model.adminQueue.proposals.filter({model.selectedShopID==nil || $0.shopID==model.selectedShopID}).isEmpty { ContentUnavailableView(model.selectedShopID==nil ? T("Alles erledigt"):T("Keine Änderungen für diesen Shop"), systemImage: "checkmark.seal", description: Text(T("Neue Vorschläge aus Codex und Claude erscheinen hier."))).frame(maxWidth: .infinity).padding(.vertical, 60) }
            ForEach(Array(proposals)) { proposal in
                Panel {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack { VStack(alignment: .leading, spacing: 5) { Text(proposal.productName).font(.system(size: 18, weight: .semibold)); Text(model.workspace.shops.first { $0.id == proposal.shopID }?.name ?? T("Shop entfernt")).font(.caption).foregroundStyle(.secondary) }; Spacer(); StatusPill(text: T(proposal.status), color: proposal.status == "pending" ? .orange : .green) }
                        Text(proposal.reason).font(.system(size: 13)).foregroundStyle(.secondary)
                        ForEach(proposal.changes.keys.sorted(), id: \.self) { key in HStack(alignment: .top) { Text(T(key)).frame(width: 110, alignment: .leading).foregroundStyle(.secondary); Text(display(proposal.changes[key]!)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.font(.system(size: 12)) }
                        if proposal.status == "pending" { HStack { Button(T("Ablehnen")) { Task { await model.resolve(proposal, apply: false) } }; Spacer(); Button(T("Prüfen und übernehmen")) { Task { busy = true; defer { busy = false }; if let shop = model.workspace.shops.first(where: { $0.id == proposal.shopID }) { do { current = try await model.client.detail(shop, entity: "product", id: proposal.productID); confirming = proposal } catch { model.error = error.localizedDescription } } } }.buttonStyle(.borderedProminent).disabled(busy) } }
                        if proposal.status == "applying" { Text(T("Übernahme wurde unterbrochen. Prüfe den aktuellen Produktstand.")).font(.caption).foregroundStyle(.orange); Button(T("Erneut zur Prüfung vorlegen")) { model.mutate { state in if let i = state.proposals.firstIndex(where: { $0.id == proposal.id }) { state.proposals[i].status = "pending" } } } }
                        if proposal.status == "needs_review" { Button(T("Änderungsverlauf öffnen")) { model.destination = .history }; Text(T("Die Änderung muss im Änderungsverlauf geprüft werden.")).font(.caption).foregroundStyle(.orange) }
                    }
                }
            }
        }.padding(30) }
        .sheet(isPresented:$bulkReview){BulkProposalReviewView(model:model)}
        .sheet(item: $confirming) { proposal in
            VStack(alignment: .leading, spacing: 22) {
                Text(T("Änderungen übernehmen?")).font(.title2.bold()); Text(proposal.productName).foregroundStyle(.secondary)
                ForEach(proposal.changes.keys.sorted(), id: \.self) { key in VStack(alignment: .leading, spacing: 6) { Text(T(key)).font(.headline); HStack(alignment: .top) { Text(display(current?[key] ?? .null)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading); Image(systemName: "arrow.right"); Text(display(proposal.changes[key]!)).frame(maxWidth: .infinity, alignment: .leading) }.font(.system(size: 12)).textSelection(.enabled) } }
                HStack { Button(T("Abbrechen")) { confirming = nil }; Spacer(); Button(T("Jetzt übernehmen")) { Task { busy = true; await model.resolve(proposal, apply: true,reviewedBefore:Dictionary(uniqueKeysWithValues:proposal.changes.keys.map{($0,current?[$0] ?? .null)})); busy = false; confirming = nil } }.buttonStyle(.borderedProminent).disabled(busy) }
            }.padding(30).frame(width: 650)
        }
    }
    private var scopedPending:Int{model.workspace.proposals.filter{$0.status=="pending" && (model.selectedShopID==nil || $0.shopID==model.selectedShopID)}.count+model.adminQueue.proposals.filter{$0.status=="pending" && (model.selectedShopID==nil || $0.shopID==model.selectedShopID)}.count+model.automationQueue.operations.filter{$0.status=="pending" && (model.selectedShopID==nil || $0.shopID==model.selectedShopID)}.count}
    private func display(_ value: JSONValue) -> String { value.string ?? value.bool.map { $0 ? T("Aktiv") : T("Inaktiv") } ?? value.number.map { $0.formatted(.number.locale(Locale(identifier:Language.current))) } ?? "–" }
}

struct UpdatesView: View {
    @Bindable var model: AppModel
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .top) { PageTitle(title: T("Bleib auf dem neuesten Stand."), subtitle: T("Shopware Releases direkt von GitHub. Verglichen mit deinen verbundenen Shops.")); Spacer(); Button { Task { await model.checkUpdates() } } label: { Label(T("Updates prüfen"), systemImage: "arrow.clockwise") }.buttonStyle(.borderedProminent).disabled(model.checkingUpdates) }
            if model.checkingUpdates { ProgressView(T("Versionen werden geprüft …")).padding(.vertical, 20) }
            if let error = model.updateError { Text(error).font(.system(size: 12)).foregroundStyle(.orange) }
            if let latest = model.latestVersion {
                HStack { VStack(alignment: .leading, spacing: 10) { Text(T("Aktuelle stabile Version")).font(.system(size: 13)); Text(latest).font(.system(size: 40, weight: .bold, design: .rounded)); if let date = model.lastUpdateCheck { Text(T("Geprüft:") + " " + localizedDate(date,date:.abbreviated,time:.shortened)).font(.caption) } }; Spacer(); if let url = model.releaseURL { Link(T("Release Notes öffnen"), destination: url).buttonStyle(.bordered) } }.foregroundStyle(.primary).padding(24).background(Theme.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            }
            SecurityStatusView(model:model)
            ForEach(model.workspace.shops) { shop in
                HStack(spacing: 14) { ShopIcon(shop: shop, size: 38); VStack(alignment: .leading, spacing: 5) { Text(shop.name).font(.headline); Text(shop.isDemo ? T("Beispielversion im Demomodus") : shop.host).font(.caption).foregroundStyle(.secondary) }; Spacer(); if let installed = model.versions[shop.id] { Text(installed).monospacedDigit(); StatusPill(text: model.latestVersion.map { VersionComparison.isNewer($0, than: installed) } == true ? T("Update verfügbar") : T("Aktuell"), color: model.latestVersion.map { VersionComparison.isNewer($0, than: installed) } == true ? .orange : .green) } else { Text(model.versionErrors[shop.id] ?? T("Noch nicht geprüft")).font(.caption).foregroundStyle(.secondary).frame(maxWidth: 270, alignment: .trailing) } }.padding(.vertical, 12)
                Divider()
            }
            if !model.releaseNotes.isEmpty { Text(T("Was ist neu?")).font(.title3.bold()); Markdown(model.releaseNotes).markdownTheme(.gitHub).markdownTextStyle { FontSize(13) }.textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading) }
            Link(T("Shopware Update Anleitung"), destination: URL(string: "https://docs.shopware.com/en/shopware-6-en/update-guides")!)
            Text(T("Shopdeck zeigt neue Versionen an. Updates installierst du über den vorgesehenen Weg deines Shops.")).font(.caption).foregroundStyle(.secondary)
        }.padding(30) }
    }
}

struct ActivityView: View {
    @Bindable var model: AppModel
    var body: some View { ScrollView { VStack(alignment: .leading, spacing: 24) {
        PageTitle(title: T("Was sich getan hat."), subtitle: T("Verbindungen, Änderungen und Benachrichtigungen an einem Ort."))
        let entries = model.workspace.activities.filter { model.selectedShopID == nil || $0.shopID == model.selectedShopID }.reversed()
        if entries.isEmpty { ContentUnavailableView(T("Noch keine Aktivität"), systemImage: "clock") }
        ForEach(Array(entries)) { entry in HStack(alignment: .top, spacing: 14) { Image(systemName: "circle.inset.filled").font(.system(size: 11)).foregroundStyle(Theme.blue).padding(.top, 3); VStack(alignment: .leading, spacing: 6) { Text(entry.title).font(.system(size: 13, weight: .medium)); Text(entry.detail).font(.system(size: 12)).foregroundStyle(.secondary) }; Spacer(); Text(localizedDate(entry.date,date:.abbreviated,time:.shortened)).font(.system(size: 11)).foregroundStyle(.secondary) }; Divider() }
    }.padding(30) } }
}

struct AppSettingsView: View {
    var model: AppModel
    @AppStorage("language") private var language = AppLanguage.initial()
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("automaticUpdateChecks") private var automaticUpdates = true
    @AppStorage("pageSize") private var pageSize = 50
    @AppStorage("compactRows") private var compact = false
    @AppStorage("maxServerRecords") private var maxServerRecords=1000
    @AppStorage("orderPollInterval") private var polling = 60.0
    @AppStorage("notificationSound") private var sound = true
    @AppStorage("showMenuBar") private var showMenuBar = false
    @AppStorage("dockOrderBadge") private var dockOrderBadge = false
    @AppStorage(MerchantFocusPreferences.enabledKey) private var showFocus = true
    var body: some View { Form {
        Section(T("Darstellung und Sprache")) {
            Picker(T("Erscheinungsbild"), selection: $appearance) { Text(T("System")).tag("system"); Text(T("Hell")).tag("light"); Text(T("Dunkel")).tag("dark") }.pickerStyle(.segmented)
            Picker(T("Sprache"), selection: $language) { ForEach(Language.all, id: \.0) { code, name in Text(name).tag(code) } }
            Toggle(T("Kompakte Tabellenzeilen"), isOn: $compact)
        }
        Section(T("Dashboard")) {
            Toggle(T("Arbeitsvorrat anzeigen"), isOn: $showFocus)
        }
        Section(T("Listen und Daten")) {
            Picker(T("Datensätze pro Seite"), selection: $pageSize) { Text("25").tag(25); Text("50").tag(50); Text("100").tag(100) }
            Picker(T("Maximal geladene Datensätze je Shop"),selection:$maxServerRecords){ForEach([50,100,250,500,1000,5000,10000],id:\.self){Text(String($0)).tag($0)}}
            Text(T("Suche, Filter und Sortierung laufen im Shop vor der Seitenauswahl. Über mehrere Shops werden die sortierten Treffer zusammengeführt. Die Ergebnisgrenze begrenzt auch die gemeinsam durchblätterbare Trefferzahl.")).font(.caption).foregroundStyle(.secondary)
            Text(T("Spalten und Schnellfilter legst du direkt in jeder Liste unter Liste anpassen fest.")).font(.caption).foregroundStyle(.secondary)
            Button(T("Lokalen Datenordner öffnen")) { NSWorkspace.shared.open(model.store.directory) }
            Text(T("API Schlüssel liegen im macOS Schlüsselbund. Listen, Regeln und der Änderungsverlauf bleiben lokal auf diesem Mac.")).font(.caption).foregroundStyle(.secondary)
        }
        Section("macOS") {
            Toggle(T("Shopdeck in der Menüleiste"),isOn:$showMenuBar)
            Toggle(T("Bestellungen heute am Dock Icon anzeigen"),isOn:$dockOrderBadge)
            if CommerceWidgetSnapshot.canShare {
                let snapshot=CommerceWidgetSnapshot.read()
                Label(snapshot.scopes.isEmpty ? T("Widgets warten auf Statistikdaten."):T("Desktop Widgets sind verbunden.")+" \(snapshot.scopes.count) "+T("Shopansichten verfügbar."),systemImage:snapshot.scopes.isEmpty ? "clock":"checkmark.circle.fill").font(.caption).foregroundStyle(snapshot.scopes.isEmpty ? Color.secondary:Color.green)
            }
            if !CommerceWidgetSnapshot.canShare { Text(T("Die WidgetKit Erweiterung ist enthalten. Für den Datenaustausch mit macOS Widgets braucht diese lokale Version noch eine Apple Entwicklungssignierung mit App Group.")).font(.caption).foregroundStyle(.orange) }
            Text(T("Desktop Widgets: Auf dem Schreibtisch Widgets bearbeiten öffnen und Shopdeck wählen. Shop, Statistik und Währung lassen sich je Widget festlegen.")).font(.caption).foregroundStyle(.secondary)
            Text(T("Widgets zeigen den zuletzt in der App geladenen Stand mit Uhrzeit. Sie enthalten keine API Schlüssel.")).font(.caption).foregroundStyle(.secondary)
        }
        Section(T("Benachrichtigungen und Updates")) {
            Picker(T("Neue Bestellungen prüfen"), selection: $polling) { Text(T("Alle 30 Sekunden")).tag(30.0); Text(T("Jede Minute")).tag(60.0); Text(T("Alle 5 Minuten")).tag(300.0); Text(T("Alle 15 Minuten")).tag(900.0) }
            Toggle(T("Mitteilungston"), isOn: $sound)
            Toggle(T("Shopware Updates täglich prüfen"), isOn: $automaticUpdates)
            Button(T("Regeln verwalten")) { model.destination = .notifications; NSApp.keyWindow?.close() }
        }
        AppUpdateSettings()
        Section {
            Button(T("Einrichtungsassistent öffnen")){appAction("onboard");NSApp.keyWindow?.close()}
            LabeledContent(T("Version"), value: "Shopdeck " + AppVersion.current)
            Link("Shopware Community Edition", destination: URL(string: "https://www.shopware.com/en/community/community-edition/")!)
        }
    }.formStyle(.grouped).padding(12).frame(width: 680, height: 740).environment(\.locale, Locale(identifier: language)).onChange(of:dockOrderBadge){_,_ in WidgetSnapshotExporter.write(model:model)} }
}
