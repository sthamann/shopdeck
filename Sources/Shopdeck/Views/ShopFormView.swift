import SwiftUI
import ShopdeckCore

struct ShopFormView: View {
    var model: AppModel
    let existing: Shop?
    @Environment(\.dismiss) private var dismiss
    @LocalState<Bool> private var local = false
    @LocalState<String> private var name = ""
    @LocalState<String> private var url = ""
    @LocalState<String> private var clientID = ""
    @LocalState<String> private var secret = ""
    @LocalState<String> private var environment = "Produktion"
    @LocalState<String> private var color = "blue"
    @LocalState<Bool> private var mcp = false
    @LocalState<Bool> private var customerData = false
    @LocalState<UUID?> private var groupID: UUID?
    @LocalState<String?> private var favicon: String?
    @LocalState<Bool> private var busy = false
    @LocalState<String?> private var message: String?
    @LocalState<Bool> private var success = false
    @LocalState<String> private var port = "8888"
    @LocalState<Bool> private var automaticPort=true
    @LocalState<Bool> private var findingPort=false
    @LocalState<String> private var tag = "latest"
    @LocalState<DockerProvisioner> private var docker = DockerProvisioner()
    @LocalState<UUID> private var newID = UUID()
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Image(systemName: "square.stack.3d.up.fill").font(.title).foregroundStyle(Theme.blue); VStack(alignment: .leading, spacing: 5) { Text(existing == nil ? T("Ein neuer Shop. Alle Möglichkeiten.") : T("Shopeinstellungen")).font(.system(size: 23, weight: .bold)); Text(T("Dein nächster Shop ist nur eine Verbindung entfernt.")).foregroundStyle(.secondary).font(.system(size: 12)) }; Spacer() }.padding(28)
            if existing == nil { Picker("", selection: $local) { Text(T("Bestehenden Shop verbinden")).tag(false); Text(T("Lokalen Testshop erstellen")).tag(true) }.pickerStyle(.segmented).padding(.horizontal, 28).padding(.bottom, 20) }
            ScrollView {
                Form {
                    Section {
                        TextField(T("Shopname"), text: $name)
                        if !local { TextField(T("Shopadresse"), text: $url).textContentType(.URL) }
                        Picker(T("Gruppe"), selection: $groupID) { Text(T("Ohne Gruppe")).tag(nil as UUID?); ForEach(model.workspace.groups) { Text($0.name).tag(Optional($0.id)) } }
                        if !local { Picker(T("Umgebung"), selection: $environment) { ForEach(["Produktion", "Staging", "Lokal"], id: \.self) { Text(T($0)).tag($0) } } }
                        HStack {
                            Text(T("Shopfarbe")); Spacer()
                            ForEach(["blue", "orange", "mint", "purple"], id: \.self) { c in
                                Button { color = c } label: {
                                    Circle().fill(Theme.color(c)).frame(width: 20, height: 20).overlay {
                                        if color == c { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.black) }
                                    }
                                }.buttonStyle(.plain).accessibilityLabel(c)
                            }
                        }
                        if !local { HStack { Text(T("Favicon")); Spacer(); if let file = favicon, let image = NSImage(contentsOfFile: file) { Image(nsImage: image).resizable().scaledToFit().frame(width: 22, height: 22) }; Button(T("Von Domain importieren")) { Task { await importFavicon() } }.disabled(url.isEmpty || busy) } }
                    }
                    if local {
                        Section {
                            Toggle(T("Freien Port automatisch wählen"),isOn:$automaticPort)
                            TextField(T("Lokaler Port"), text: $port).disabled(automaticPort)
                            if findingPort{ProgressView(T("Vorhandene Testshops werden geprüft …"))}
                            TextField(T("Image Version"), text: $tag)
                            Text("dockware/shopware:\(tag)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            Text(T("Shopdeck installiert fehlendes Docker Desktop, startet das Image und richtet Storefront sowie API Zugang automatisch ein.")).font(.system(size: 12)).foregroundStyle(.secondary)
                            Text(T("Adminzugang für den lokalen Testshop: admin / shopware. Die Daten bleiben im Container erhalten.")).font(.system(size: 12)).foregroundStyle(.secondary)
                            Text(T("Beim ersten Start bestätigst du die Docker Lizenzbedingungen direkt in Docker. Shopdeck wartet anschließend auf die Bereitschaft." )).font(.caption).foregroundStyle(.secondary)
                            Link(T("Docker Desktop herunterladen"), destination: URL(string: "https://www.docker.com/products/docker-desktop/")!)
                        } header: { Text(T("Shopware lokal starten")) }
                    } else if existing?.isDemo != true {
                        Section {
                            TextField(T("Zugangs ID"), text: $clientID)
                            SecureField(existing == nil ? T("Sicherheitsschlüssel") : T("Neuer Sicherheitsschlüssel (optional)"), text: $secret)
                            Text(T("Shopware Administration → Einstellungen → System → Integrationen. Zugangsdaten werden im macOS Schlüsselbund gespeichert.")).font(.system(size: 12)).foregroundStyle(.secondary)
                            Button(T("Verbindung testen")) { Task { await test() } }.disabled(busy || url.isEmpty)
                        } header: { Text(T("Admin API Verbindung")) }
                    }
                    if !local {
                        Section {
                            Toggle(T("Für Codex und Claude freigeben"), isOn: $mcp)
                            Toggle(T("Kundendaten über MCP teilen"), isOn: $customerData).disabled(!mcp)
                            Text(T("Ohne diese Freigabe bleiben Namen, E Mail Adressen und Adressen für KI Clients verborgen.")).font(.system(size: 11)).foregroundStyle(.secondary)
                        } header: { Text(T("KI Zugriff")) }
                    }
                    if let container = existing?.containerName {
                        Section {
                            Text(container).font(.system(.body, design: .monospaced))
                            HStack { Button(T("Starten")) { containerAction("start", container) }; Button(T("Stoppen")) { containerAction("stop", container) }; Link(T("Administration öffnen"), destination: URL(string: existing!.url)!.appendingPathComponent("admin")) }
                        } header: { Text(T("Lokaler Container")) }
                    }
                }.formStyle(.grouped)
                if let message { Label(message, systemImage: success ? "checkmark.circle" : "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(success ? .green : .orange).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 28).padding(.bottom, 15) }
                if docker.busy { HStack { ProgressView().controlSize(.small); Text(docker.stage).font(.system(size: 12)) }.padding(.bottom, 20) }
                if let failure = docker.failure { Text(failure).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled).padding(.horizontal, 28); if let container = docker.container { Text(T("Container bleibt für die Diagnose erhalten:") + " " + container).font(.caption).textSelection(.enabled).padding(16) } }
            }
            Divider()
            HStack { Link("Community Edition ↗", destination: URL(string: "https://www.shopware.com/en/community/community-edition/")!).font(.system(size: 12)); Spacer(); Button(T("Abbrechen")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(docker.busy); Button(local ? T("Testshop erstellen") : T("Speichern")) { Task { if local { if let shop = await docker.create(name: name, port: Int(port) ?? 0, tag: tag, model: model,automaticPort:automaticPort) { model.selectedShopID = shop.id; dismiss() } } else { await save() } } }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(busy || docker.busy || findingPort || (!local && (name.isEmpty || url.isEmpty))) }.padding(22)
        }.frame(width: 650, height: 730).interactiveDismissDisabled(docker.busy || busy)
        .task(id:local){if local,existing==nil{findingPort=true;let suggestion=await LocalShopDiscovery.suggest(model:model);if name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty{name=suggestion.name};if automaticPort,let suggested=suggestion.port{port=String(suggested)};findingPort=false}}
        .onAppear { if existing == nil {local=model.startWithLocalShop;model.startWithLocalShop=false};if let shop = existing { name = shop.name; url = shop.url; environment = shop.environment; color = shop.color; mcp = shop.mcpEnabled; customerData = shop.shareCustomerData; groupID = shop.groupID; favicon = shop.faviconFile; newID = shop.id } }
    }
    private func makeShop() throws -> Shop {
        let normalized = try Validation.shopURL(url).absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var shop = Shop(id: newID, name: name.trimmingCharacters(in: .whitespacesAndNewlines), url: normalized, environment: environment, color: color, isDemo: existing?.isDemo ?? false, mcpEnabled: mcp, shareCustomerData: customerData)
        guard !shop.name.isEmpty else { throw ShopdeckError.message(T("Bitte gib einen Shopnamen ein.")) }
        shop.groupID = groupID; shop.faviconFile = favicon; shop.containerName = existing?.containerName; return shop
    }
    private func credential() throws -> Credentials {
        if !clientID.isEmpty && !secret.isEmpty { return Credentials(clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines), clientSecret: secret) }
        if existing != nil, clientID.isEmpty, secret.isEmpty { return try KeychainStore().load(for: newID) }
        throw ShopdeckError.message(T("Bitte gib Zugangs ID und Sicherheitsschlüssel ein."))
    }
    private func test() async {
        busy = true; defer { busy = false }
        do { try await model.client.testConnection(makeShop(), credentials: credential()); message = T("Verbindung erfolgreich."); success = true }
        catch { message = error.localizedDescription; success = false }
    }
    private func save() async {
        busy = true; defer { busy = false }
        do {
            let shop = try makeShop()
            let credentials = shop.isDemo ? nil : try credential()
            if let credentials { try await model.client.testConnection(shop, credentials: credentials) }
            try await model.saveShop(shop, credentials: credentials); dismiss()
        } catch { message = error.localizedDescription; success = false }
    }
    private func importFavicon() async {
        busy = true; defer { busy = false }
        do {
            let base = try Validation.shopURL(url)
            let icon = base.appendingPathComponent("favicon.ico")
            let (data, response) = try await URLSession.shared.data(from: icon)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 2_000_000, let image = NSImage(data: data), let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { throw ShopdeckError.message(T("Kein lesbares Favicon unter /favicon.ico gefunden.")) }
            let directory = model.store.directory.appendingPathComponent("icons"); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent(newID.uuidString + ".png"); try png.write(to: file, options: .atomic); favicon = file.path; message = T("Favicon importiert."); success = true
        } catch { message = error.localizedDescription; success = false }
    }
    private func containerAction(_ action: String, _ name: String) { Task { guard let docker = LocalCommand.docker else { return }; busy = true; defer { busy = false }; do { _ = try await LocalCommand.run(docker, [action, name], timeout: 45); message = T("Container aktualisiert."); success = true } catch { message = error.localizedDescription; success = false } } }
}
