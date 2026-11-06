import Foundation
import Observation
import ShopdeckCore

enum LocalCommand {
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 600, input: Data? = nil) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("shopdeck-process-\(UUID().uuidString).log")
            FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
            do {
                let output = try FileHandle(forWritingTo: file)
                process.standardOutput = output; process.standardError = output
                process.terminationHandler = { process in
                    try? output.close()
                    let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
                    try? FileManager.default.removeItem(at: file)
                    if process.terminationStatus == 0 { continuation.resume(returning: text) }
                    else { continuation.resume(throwing: ShopdeckError.message(String(text.suffix(2500)))) }
                }
                let stdin = Pipe(); process.standardInput = stdin
                try process.run()
                if let input { stdin.fileHandleForWriting.write(input) }
                try? stdin.fileHandleForWriting.close()
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if process.isRunning { process.terminate() } }
            } catch { try? FileManager.default.removeItem(at: file); continuation.resume(throwing: error) }
        }
    }
    static var docker: String? { [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".docker/bin/docker").path,"/usr/local/bin/docker", "/opt/homebrew/bin/docker", "/Applications/Docker.app/Contents/Resources/bin/docker",FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Docker.app/Contents/Resources/bin/docker").path].first { FileManager.default.isExecutableFile(atPath: $0) } }
}
@MainActor @Observable final class DockerProvisioner {
    var busy = false
    var stage = ""
    var container: String?
    var failure: String?
    func create(name: String, port: Int, tag: String, model: AppModel,automaticPort:Bool=true) async -> Shop? {
        guard (1024...65535).contains(port), tag.range(of: "^[A-Za-z0-9][A-Za-z0-9_.-]{0,80}$", options: .regularExpression) != nil else { failure = T("Prüfe Port und Image Version."); return nil }
        busy = true; failure = nil; defer { busy = false }
        do {
            var port=port
            if automaticPort {let suggestion=await LocalShopDiscovery.suggest(model:model);guard let available=suggestion.port else{throw ShopdeckError.message(T("Kein freier lokaler Port gefunden."))};port=available}
            else if !LocalShopSuggestion.available(port){throw ShopdeckError.message(T("Dieser Port ist bereits belegt. Wähle einen freien Port oder die automatische Auswahl."))}
            stage=T("Docker wird geprüft …")
            var executable=LocalCommand.docker
            if executable==nil {let app=try await OfficialDockerInstaller.install{self.stage=$0};try await OfficialDockerInstaller.start(app);executable=LocalCommand.docker}
            guard let docker=executable else{throw ShopdeckError.message(T("Docker konnte nicht gefunden werden."))}
            if (try? await LocalCommand.run(docker,["info","--format","{{.ServerVersion}}"],timeout:5)) == nil {
                if let app=OfficialDockerInstaller.appURL{try await OfficialDockerInstaller.start(app)}
                stage=T("Docker wird gestartet. Schließe die Ersteinrichtung im Docker Fenster ab.")
                var ready=false
                for _ in 0..<120 {try Task.checkCancellation();if (try? await LocalCommand.run(docker,["info","--format","{{.ServerVersion}}"],timeout:3)) != nil{ready=true;break};try await Task.sleep(for:.seconds(3))}
                guard ready else{throw ShopdeckError.message(T("Docker ist noch nicht bereit. Schließe die Ersteinrichtung ab und versuche es erneut."))}
            }
            if let context=try? await LocalCommand.run(docker,["context","inspect","--format","{{.Endpoints.docker.Host}}"],timeout:5),!context.trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("unix://"){throw ShopdeckError.message(T("Wähle in Docker einen lokalen Kontext für diesen Testshop."))}
            stage = T("Shopware Image wird geladen …")
            let image = "dockware/shopware:\(tag)"
            _ = try await LocalCommand.run(docker, ["pull", image], timeout: 1200)
            let id = UUID(), containerName = "shopdeck-" + id.uuidString.prefix(8).lowercased()
            if automaticPort{let suggestion=await LocalShopDiscovery.suggest(model:model);guard let available=suggestion.port else{throw ShopdeckError.message(T("Kein freier lokaler Port gefunden."))};port=available}else if !LocalShopSuggestion.available(port){throw ShopdeckError.message(T("Dieser Port ist inzwischen belegt. Wähle einen freien Port."))}
            stage = T("Testshop wird gestartet …")
            _ = try await LocalCommand.run(docker, ["run", "-d", "--name", containerName, "--label", "app.shopdeck.managed=true", "-e","APP_URL=http://127.0.0.1:\(port)", "-p", "127.0.0.1:\(port):80", image], timeout: 60)
            container = containerName
            var shop = Shop(id: id, name: name.isEmpty ? T("Lokaler Testshop") : name, url: "http://127.0.0.1:\(port)", environment: "Lokal", color: "mint", mcpEnabled: true)
            shop.containerName = containerName
            stage = T("Shopware startet. Das kann einige Minuten dauern …")
            var credentials: Credentials?
            var lastError = ""
            for _ in 0..<90 {
                do { credentials = try await model.client.bootstrapLocal(shop); break }
                catch { lastError = error.localizedDescription; try await Task.sleep(for: .seconds(3)) }
            }
            guard let credentials else { throw ShopdeckError.message(T("Shopware ist noch nicht bereit.") + " " + lastError) }
            try await model.client.configureLocalDomains(shop,credentials:credentials)
            stage = T("API Verbindung wird gespeichert …")
            try await model.saveShop(shop, credentials: credentials)
            stage = T("Dein lokaler Shop ist bereit.")
            return shop
        } catch { failure = error.localizedDescription; return nil }
    }
}
