import Foundation

public struct ClientInstallationStatus:Sendable {
    public let mcpConfigured:Bool
    public let skillInstalled:Bool
}
extension ClientInstaller {
    public func status(_ client:AIClient,destination:URL)->ClientInstallationStatus {
        let fm=FileManager.default
        var configured=false
        switch client {
        case .codex:
            let file=home.appendingPathComponent(".codex/config.toml"),text=(try? String(contentsOf:file,encoding:.utf8)) ?? ""
            if let range=text.range(of:"(?ms)^\\[mcp_servers\\.shopdeck\\]\\s*\\n.*?(?=^\\[|\\z)",options:.regularExpression){configured=text[range].contains("command = \""+destination.path+"\"")}
        case .claudeCode,.claudeDesktop:
            let file=home.appendingPathComponent(client == .claudeCode ? ".claude.json":"Library/Application Support/Claude/claude_desktop_config.json")
            if let data=try? Data(contentsOf:file),let object=try? JSONSerialization.jsonObject(with:data) as? [String:Any],let servers=object["mcpServers"] as? [String:Any],let server=servers["shopdeck"] as? [String:Any]{configured=server["command"] as? String == destination.path}
        }
        let skill=home.appendingPathComponent(client == .codex ? ".agents/skills/shopdeck/SKILL.md":".claude/skills/shopdeck/SKILL.md")
        return .init(mcpConfigured:configured && fm.isExecutableFile(atPath:destination.path),skillInstalled:client != .claudeDesktop && fm.fileExists(atPath:skill.path))
    }
    public func updateRuntime(helper:URL,destination:URL)throws {
        let fm=FileManager.default;try fm.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
        for name in ["shopdeck-mcp","shopdeck-keychain"] {
            let source=helper.deletingLastPathComponent().appendingPathComponent(name),target=destination.deletingLastPathComponent().appendingPathComponent(name)
            guard fm.isExecutableFile(atPath:source.path) else{throw ShopdeckError.message("Ein Laufzeithelfer fehlt im App Paket.")}
            let data=try Data(contentsOf:source)
            if (try? Data(contentsOf:target)) != data {try data.write(to:target,options:.atomic);try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:target.path)}
        }
    }
}
