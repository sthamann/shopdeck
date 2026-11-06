import AppKit
import ShopdeckCore

struct ClientAvailability:Sendable {
    var present:Bool
    var detail:String
    var appURL:URL?
    var executable:URL?
}
enum ClientDiscovery {
    @MainActor static func detect(_ client:AIClient) async -> ClientAvailability {
        let fm=FileManager.default,home=fm.homeDirectoryForCurrentUser
        let bundle=client == .codex ? "com.openai.codex":"com.anthropic.claudefordesktop"
        let app=client == .claudeCode ? nil:NSWorkspace.shared.urlForApplication(withBundleIdentifier:bundle)
        if let app,let bundle=Bundle(url:app),let executable=bundle.executableURL,fm.isExecutableFile(atPath:executable.path) {return .init(present:true,detail:(bundle.infoDictionary?["CFBundleShortVersionString"] as? String).map{"Version "+$0} ?? T("App gefunden"),appURL:app,executable:nil)}
        let binary=client == .codex ? "codex":"claude"
        let roots=["/opt/homebrew/bin","/usr/local/bin",home.appendingPathComponent(".local/bin").path,home.appendingPathComponent(".claude/local").path]
        if client != .claudeDesktop,let file=roots.map({URL(fileURLWithPath:$0).appendingPathComponent(binary)}).first(where:{fm.isExecutableFile(atPath:$0.path)}) {
            do {let version=try await LocalCommand.run(file.path,["--version"],timeout:4);return .init(present:true,detail:String(version.trimmingCharacters(in:.whitespacesAndNewlines).prefix(100)),appURL:nil,executable:file)} catch {return .init(present:false,detail:T("Programm konnte nicht gestartet werden"),appURL:nil,executable:file)}
        }
        return .init(present:false,detail:T("Nicht installiert"),appURL:nil,executable:nil)
    }
}
