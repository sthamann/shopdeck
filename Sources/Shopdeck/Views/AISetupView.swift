import SwiftUI
import ShopdeckCore
import UniformTypeIdentifiers

struct AISetupView: View {
    @Bindable var model: AppModel
    @LocalState<AIClient> private var selectedClient = .codex
    @LocalState<AIClient?> private var installing: AIClient?
    @LocalState<Set<String>> private var installed: Set<String> = []
    @LocalState<[AIClient:ClientAvailability]> private var availability: [AIClient:ClientAvailability] = [:]
    @LocalState<String> private var result = ""
    @LocalState<String> private var resultDetails = ""
    @LocalState<Bool> private var testing = false
    @LocalState<Bool> private var checked = false
    @LocalState<[JSONValue]> private var tools = MCPServer.tools
    @LocalState<String> private var toolSearch = ""
    @LocalState<UUID?> private var officialShop: UUID? = nil
    @LocalState<[JSONValue]> private var officialTools: [JSONValue] = []
    @LocalState<String> private var officialResult = ""
    @LocalState<Bool> private var checkingOfficial = false
    private var helper: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/shopdeck-mcp") }
    private var installedHelper: URL { model.store.directory.appendingPathComponent("bin/shopdeck-mcp") }
    private var permittedShops:[Shop] {model.workspace.shops.filter(\.mcpEnabled)}
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:24) {
                HStack(alignment:.top,spacing:18) {
                    VStack(alignment:.leading,spacing:7) {Text("Codex & Claude").font(.system(size:28,weight:.bold,design:.rounded));Text(T("Verbinde deine KI mit allen freigegebenen Shops.")).font(.system(size:13)).foregroundStyle(.secondary)}
                    Spacer();Label(T("Lokal auf diesem Mac"),systemImage:"lock.shield").font(.caption).foregroundStyle(.secondary)
                }
                connectionStatus
                ViewThatFits(in:.horizontal) {
                    HStack(alignment:.top,spacing:24) {setupPanel.frame(minWidth:440,maxWidth:.infinity);shopPermissions.frame(width:280)}
                    VStack(alignment:.leading,spacing:24) {setupPanel;shopPermissions}
                }
                usageGuide
                toolCatalogue
                officialCatalogue
                DisclosureGroup(T("Manuelle Konfiguration")) { VStack(alignment:.leading,spacing:12) {Text("Codex · ~/.codex/config.toml").font(.caption);codeBlock("[mcp_servers.shopdeck]\ncommand = \"\(installedHelper.path)\"");Text("Claude Desktop · claude_desktop_config.json").font(.caption);codeBlock("{\"mcpServers\":{\"shopdeck\":{\"command\":\"\(installedHelper.path)\",\"args\":[]}}}")}.padding(.top,12) }
            }.frame(maxWidth:1120,alignment:.leading).padding(28).frame(maxWidth:.infinity,alignment:.topLeading)
        }.task {await scanClients()}
    }
    private var connectionStatus:some View {
        HStack(spacing:14) {
            Image(systemName:checked ? "checkmark.circle.fill":"point.3.connected.trianglepath.dotted").font(.system(size:27,weight:.medium)).foregroundStyle(checked ? .green:Theme.blue)
            VStack(alignment:.leading,spacing:5) {Text(T("MCP Verbindung")).font(.system(size:15,weight:.semibold));Text(testing ? T("Verbindung wird geprüft …"):checked ? "\(tools.count) "+T("Werkzeuge vom Server bestätigt"):T("Prüfe den lokalen Server, bevor du einen Client verbindest.")).font(.system(size:12)).foregroundStyle(.secondary)}
            Spacer();if testing{ProgressView().controlSize(.small)}
            Button{Task{await probe()}}label:{Label(checked ? T("Erneut prüfen"):T("Jetzt prüfen"),systemImage:"arrow.triangle.2.circlepath")}.buttonStyle(.borderedProminent).controlSize(.large).disabled(testing)
        }.padding(18).background(Theme.blue.opacity(0.075),in:RoundedRectangle(cornerRadius:12))
    }
    private var setupPanel:some View {
        VStack(alignment:.leading,spacing:22) {
            Picker(T("Client"),selection:$selectedClient) {ForEach(AIClient.allCases,id:\.rawValue){Text($0.rawValue).tag($0)}}.pickerStyle(.segmented)
            HStack(alignment:.top,spacing:14) {
                Image(systemName:selectedClient == .codex ? "terminal":"asterisk").font(.system(size:28,weight:.medium)).foregroundStyle(selectedClient == .codex ? Theme.blue:.orange).frame(width:40,height:40)
                VStack(alignment:.leading,spacing:6) {Text(selectedClient.rawValue).font(.system(size:22,weight:.semibold));if let state=availability[selectedClient]{Label(state.present ? T("Installiert"):state.detail,systemImage:state.present ? "checkmark.circle.fill":"arrow.down.circle").font(.caption).foregroundStyle(state.present ? Color.secondary:Color.orange);if state.present{Text(state.detail).font(.caption).foregroundStyle(.secondary)}}else{Text(T("Installation wird geprüft …")).font(.caption).foregroundStyle(.secondary)}}
                Spacer()
            }
            VStack(alignment:.leading,spacing:13) {
                setupLine("link",T("MCP Verbindung automatisch eintragen"))
                setupLine("sparkles",selectedClient == .claudeDesktop ? T("Skill als ZIP für Claude Desktop exportieren"):T("Shopdeck Skill automatisch installieren"))
                setupLine("arrow.uturn.backward",T("Bestehende Konfiguration vorher sichern"))
            }.font(.system(size:13))
            if !result.isEmpty { VStack(alignment:.leading,spacing:7) {Label(result,systemImage:"checkmark.circle.fill").font(.system(size:13,weight:.semibold)).foregroundStyle(.green);if !resultDetails.isEmpty{DisclosureGroup(T("Details anzeigen")){Text(resultDetails).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)}}}.padding(.vertical,2) }
            Divider()
            HStack {
                if availability[selectedClient]?.present == false {Link(T("Client herunterladen"),destination:URL(string:selectedClient == .codex ? "https://chatgpt.com/codex":"https://claude.com/download")!).buttonStyle(.bordered)}
                Button{Task{await scanClients()}}label:{Image(systemName:"arrow.clockwise")}.buttonStyle(.borderless).help(T("Installierte Clients erneut prüfen"))
                Spacer()
                Button{install(selectedClient)}label:{if installing==selectedClient{ProgressView().controlSize(.small)}else{Text(selectedClient.rawValue+" "+(installed.contains(selectedClient.rawValue) ? T("aktualisieren"):T("einrichten")))}}.buttonStyle(.borderedProminent).controlSize(.large).disabled(installing != nil || availability[selectedClient]?.present != true)
            }
            if selectedClient == .claudeDesktop {Button(T("Claude Desktop Skill exportieren")){Task{await exportSkill()}};Text(T("Den Skill importierst du in Claude Desktop unter Einstellungen → Fähigkeiten → Skills.")).font(.caption).foregroundStyle(.secondary)}
        }.padding(22).background(Theme.surface,in:RoundedRectangle(cornerRadius:12))
    }
    private var usageGuide:some View {
        VStack(alignment:.leading,spacing:18) {
            Label(T("So probierst du es aus"),systemImage:"play.circle.fill").font(.system(size:19,weight:.semibold))
            HStack(alignment:.top,spacing:24) {
                guideStep("1",T("Einrichten und freigeben"),T("Richte deinen Client oben ein und aktiviere MCP Zugriff für die gewünschten Shops."))
                guideStep("2",T("Client neu starten"),T("Beende Codex oder Claude vollständig, öffne die App erneut und starte einen neuen Chat. In Claude Code startest du eine neue Sitzung."))
                guideStep("3",T("Mit einem Prompt testen"),T("Kopiere ein Beispiel in deinen Chat. Die Antwort soll die freigegebenen Shops oder echte Daten aus dem ausgewählten Shop enthalten."))
            }
            prompt(T("Verbindung testen"),T("Nutze Shopdeck und liste meine freigegebenen Shops mit Namen und Shop ID auf. Ändere keine Daten."))
            prompt(T("Mehrere Shops vergleichen"),T("Vergleiche mit Shopdeck die Bestellungen meiner freigegebenen Shops aus den letzten 7 Tagen. Gruppiere nach Shop, Verkaufskanal und Währung. Nutze die Admin API, falls nötig."))
            prompt(T("Kampagne mit Bild vorbereiten"),T("Erstelle mit Shopdeck für [Shopname] eine Kampagne aus Text, dem lokalen Bild [Dateipfad] und vier vorhandenen Produkten. Nutze propose_campaign, speichere einen Entwurf und zeige mir den Antrag zur Freigabe."))
            prompt(T("Änderung ausprobieren"),T("Suche mit Shopdeck im Shop [Shopname] das Produkt [Produktnummer] und schlage eine neue Beschreibung vor. Lege den Vorschlag zur Freigabe in Shopdeck vor."))
            Text(T("Lesen funktioniert direkt. Änderungen erscheinen in Shopdeck unter Änderungen und werden erst nach deiner Freigabe ausgeführt. Nenne bei mehreren Shops immer den Shopnamen oder die Shop ID.")).font(.caption).foregroundStyle(.secondary)
        }.padding(22).background(Theme.surface,in:RoundedRectangle(cornerRadius:12))
    }
    private func guideStep(_ number:String,_ title:String,_ detail:String)->some View {VStack(alignment:.leading,spacing:8){Text(number).font(.caption.bold()).foregroundStyle(Theme.blue).padding(7).background(Theme.blue.opacity(0.1),in:Circle());Text(title).font(.system(size:13,weight:.semibold));Text(detail).font(.system(size:12)).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)}.frame(maxWidth:.infinity,alignment:.topLeading)}
    private func prompt(_ title:String,_ value:String)->some View {VStack(alignment:.leading,spacing:7){Text(title).font(.caption.weight(.semibold));codeBlock(value)}}
    private func setupLine(_ icon:String,_ title:String)->some View {HStack(spacing:11){Image(systemName:icon).foregroundStyle(Theme.blue).frame(width:20);Text(title)}}
    private var shopPermissions:some View {
        VStack(alignment:.leading,spacing:17) {
            HStack {Text(T("Freigegebene Shops")).font(.system(size:15,weight:.semibold));Spacer();Text("\(permittedShops.count) / \(model.workspace.shops.count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)}
            Text(T("Jeder Aufruf wählt einen Shop über seine ID. Mehrere Shops bleiben eindeutig getrennt.")).font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(3)
            ForEach(model.workspace.shops){shop in
                HStack(spacing:10) {ShopIcon(shop:shop,size:27);VStack(alignment:.leading,spacing:3){Text(shop.name).font(.system(size:12,weight:.medium)).lineLimit(1);Text(shop.isDemo ? T("Demodaten"):shop.host).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)};Spacer();Toggle(T("MCP Zugriff"),isOn:Binding(get:{model.workspace.shops.first{$0.id==shop.id}?.mcpEnabled ?? false},set:{enabled in model.mutate{state in if let index=state.shops.firstIndex(where:{$0.id==shop.id}){state.shops[index].mcpEnabled=enabled}}})).labelsHidden().toggleStyle(.switch).controlSize(.mini).accessibilityLabel(shop.name+": "+T("MCP Zugriff"))}
            }
        }.padding(20).background(Theme.surface,in:RoundedRectangle(cornerRadius:12))
    }
    private var toolCatalogue:some View {
        VStack(alignment:.leading,spacing:15) {
            HStack {Text(T("Verfügbare Werkzeuge")).font(.system(size:18,weight:.semibold));Text("\(tools.count)").font(.caption).foregroundStyle(.secondary);Spacer();TextField(T("Werkzeuge durchsuchen …"),text:$toolSearch).textFieldStyle(.roundedBorder).frame(maxWidth:260)}
            Text(T("Die allgemeine Admin API erreicht alle Datenarten und Endpunkte des Shops. Schreibaktionen werden unter Änderungen zur Freigabe vorgelegt.")).font(.system(size:12)).foregroundStyle(.secondary).lineSpacing(3)
            ForEach(tools.filter{toolSearch.isEmpty || $0.pretty.localizedCaseInsensitiveContains(toolSearch)},id:\.pretty){tool in
                DisclosureGroup {Text(tool["inputSchema"].pretty).font(.system(size:11,design:.monospaced)).foregroundStyle(.secondary).textSelection(.enabled).padding(12)} label:{HStack(spacing:12){Image(systemName:tool["annotations"]["readOnlyHint"].bool == true ? "magnifyingglass":"checkmark.seal").foregroundStyle(Theme.blue).frame(width:20);VStack(alignment:.leading,spacing:4){Text(tool["name"].string ?? "").font(.system(size:12,weight:.medium));Text(tool["description"].string ?? "").font(.system(size:11)).foregroundStyle(.secondary).lineLimit(2)};Spacer();Text(tool["annotations"]["readOnlyHint"].bool == true ? T("Lesen"):T("Freigabe")).font(.caption).foregroundStyle(.secondary)}}
                Divider()
            }
        }
    }
    private var officialCatalogue:some View {
        VStack(alignment:.leading,spacing:14) {
            HStack {Text(T("Offizieller Shopware MCP")).font(.system(size:18,weight:.semibold));Spacer();Picker(T("Shop"),selection:$officialShop){Text(T("Shop auswählen")).tag(nil as UUID?);ForEach(model.workspace.shops.filter{!$0.isDemo}){Text($0.name).tag(Optional($0.id))}}.frame(maxWidth:240);Button(T("Shopware prüfen")){Task{await inspectOfficial()}}.disabled(officialShop==nil || checkingOfficial)}
            Text(T("Shopware lädt Werkzeuge je Sitzung nach. Die sichtbare Auswahl hängt zusätzlich von Version, Integration und Berechtigungen ab.")).font(.caption).foregroundStyle(.secondary)
            if checkingOfficial{ProgressView().controlSize(.small)}
            if !officialResult.isEmpty{Text(officialResult).font(.system(size:12)).foregroundStyle(.secondary)}
            ForEach(officialTools,id:\.pretty){tool in HStack {Text(tool["name"].string ?? "").font(.system(size:12,weight:.medium));Spacer();VStack(alignment:.leading,spacing:5){Text(tool["description"].string ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(2);Label(tool["session_available"].bool==true ? T("In dieser Sitzung verfügbar"):T("Nur im Katalog gemeldet"),systemImage:tool["session_available"].bool==true ? "checkmark.circle":"info.circle").font(.caption).foregroundStyle(tool["session_available"].bool==true ? Color.green:Color.orange)}.frame(maxWidth:600,alignment:.leading)}}
        }.padding(.top,4)
    }
    private func scanClients()async {for client in AIClient.allCases{availability[client]=await ClientDiscovery.detect(client);let status=ClientInstaller().status(client,destination:installedHelper);if status.mcpConfigured{installed.insert(client.rawValue)}else{installed.remove(client.rawValue)}}}
    private func inspectOfficial()async {guard let shop=model.workspace.shops.first(where:{$0.id==officialShop})else{return};checkingOfficial=true;defer{checkingOfficial=false};do{officialTools=try await model.client.officialMCPTools(shop);officialResult="\(officialTools.count) "+T("Werkzeuge direkt vom Shop gemeldet")}catch{officialResult=error.localizedDescription;officialTools=[]}}
    private func codeBlock(_ text: String) -> some View { HStack(alignment: .top) { Text(text).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading); Button { copyText(text) } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.borderless).help(T("Kopieren")) }.padding(15).background(Theme.surface, in: RoundedRectangle(cornerRadius: 8)) }
    private func install(_ client: AIClient) {
        installing = client
        Task {
            defer { installing = nil }
            do { let files = try ClientInstaller().install(client, helper: helper, destination: installedHelper); let status=ClientInstaller().status(client,destination:installedHelper);guard status.mcpConfigured,client == .claudeDesktop || status.skillInstalled else{throw ShopdeckError.message(T("Die Einrichtung konnte nicht vollständig bestätigt werden."))};installed.insert(client.rawValue);result=client.rawValue+" "+T("ist eingerichtet. Starte den Client neu.");resultDetails=files.joined(separator:"\n");model.notice=result }
            catch { model.error = error.localizedDescription }
        }
    }
    private func probe() async {
        testing = true; defer { testing = false }
        do {
            let initialize = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{},\"clientInfo\":{\"name\":\"shopdeck-check\",\"version\":\"1\"}}}\n"
            let list = "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}\n"
            resultDetails=""
            let runtime=FileManager.default.isExecutableFile(atPath:installedHelper.path) ? installedHelper:helper
            let output = try await LocalCommand.run(runtime.path, [], timeout: 15, input: Data((initialize + list).utf8))
            let responses = output.split(separator: "\n").compactMap { try? JSONDecoder().decode(JSONValue.self, from: Data($0.utf8)) }
            guard let response = responses.first(where: { $0["id"].number == 2 }), !response["result"]["tools"].array.isEmpty else { throw ShopdeckError.message(T("Der MCP Server hat nicht korrekt geantwortet.")) }
            tools=response["result"]["tools"].array;checked=true;model.notice=T("MCP Server antwortet.")+" \(tools.count) "+T("Werkzeuge verfügbar.")
        } catch {checked=false;model.error = error.localizedDescription }
    }
    private func exportSkill() async {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.zip]; panel.nameFieldStringValue = "shopdeck-skill.zip"
        guard panel.runModal() == .OK, let output = panel.url else { return }
        do {
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("shopdeck")
            try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: temp.deletingLastPathComponent()) }
            try ClientInstaller.skill.write(to: temp.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            _ = try await LocalCommand.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", temp.path, output.path], timeout: 20)
            model.notice = T("Skill exportiert. Importiere die ZIP Datei in Claude Desktop.")
        } catch { model.error = error.localizedDescription }
    }
}
