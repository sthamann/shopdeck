import AppKit
import Foundation
import ShopdeckCore

/// Downloads only Docker's official, signed installer. First-run license acceptance remains in Docker.
@MainActor enum OfficialDockerInstaller {
    static var appURL:URL? {let fm=FileManager.default;return [URL(fileURLWithPath:"/Applications/Docker.app"),fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Docker.app")].first{fm.fileExists(atPath:$0.path)}}
    static func install(stage:@escaping(String)->Void)async throws->URL {
        if let appURL{return appURL}
        #if arch(arm64)
        let architecture="arm64"
        #else
        let architecture="amd64"
        #endif
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("shopdeck-docker-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]);defer{try? FileManager.default.removeItem(at:root)}
        stage(T("Docker Desktop wird von docker.com geladen …"))
        let dmg=root.appendingPathComponent("Docker.dmg")
        _ = try await LocalCommand.run("/usr/bin/curl",["--fail","--location","--proto","=https","--tlsv1.2","--retry","2","--output",dmg.path,"https://desktop.docker.com/mac/main/"+architecture+"/Docker.dmg"],timeout:1800)
        try Task.checkCancellation();stage(T("Docker Installer wird geprüft …"))
        _ = try await LocalCommand.run("/usr/bin/hdiutil",["verify",dmg.path],timeout:180)
        let mount=root.appendingPathComponent("volume");try FileManager.default.createDirectory(at:mount,withIntermediateDirectories:true)
        _ = try await LocalCommand.run("/usr/bin/hdiutil",["attach","-nobrowse","-readonly","-mountpoint",mount.path,dmg.path],timeout:180)
        do {
            let app=mount.appendingPathComponent("Docker.app")
            _ = try await LocalCommand.run("/usr/bin/codesign",["--verify","--deep","--strict",app.path],timeout:120)
            _ = try await LocalCommand.run("/usr/sbin/spctl",["--assess","--type","execute",app.path],timeout:120)
            let signature=try await LocalCommand.run("/usr/bin/codesign",["-dv","--verbose=4",app.path],timeout:20)
            guard signature.contains("TeamIdentifier=9BNSXJN65R") else{throw ShopdeckError.message(T("Die Docker Signatur konnte nicht bestätigt werden."))}
            stage(T("Docker Desktop wird im Programme Ordner installiert …"))
            let destination=FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Docker.app")
            try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
            guard !FileManager.default.fileExists(atPath:destination.path) else{throw ShopdeckError.message(T("Docker ist bereits vorhanden. Starte die Einrichtung erneut."))}
            _ = try await LocalCommand.run("/usr/bin/ditto",[app.path,destination.path],timeout:300)
            _ = try await LocalCommand.run("/usr/bin/hdiutil",["detach",mount.path],timeout:30)
            return destination
        } catch {_ = try? await LocalCommand.run("/usr/bin/hdiutil",["detach",mount.path],timeout:30);throw error}
    }
    static func start(_ app:URL)async throws {let config=NSWorkspace.OpenConfiguration();config.activates=true;_ = try await NSWorkspace.shared.openApplication(at:app,configuration:config)}
}
