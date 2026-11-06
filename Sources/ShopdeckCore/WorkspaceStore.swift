import Foundation
import Security
import Darwin

/// A separate lock inode protects atomic JSON replacement across the app and MCP processes.
public final class WorkspaceStore: @unchecked Sendable {
    public let directory: URL
    private let localLock = NSLock()
    public init(directory: URL? = nil) throws {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Shopdeck", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    public func read() throws -> Workspace { try locked { try readUnlocked() } }
    public func readWorkbench() throws -> Workbench { try locked { try readLocalFile("workbench.json", fallback: Workbench()) } }
    public func readProductJournal() throws -> ProductJournal { try locked { try readLocalFile("product-changes.json", fallback: ProductJournal()) } }
    @discardableResult public func updateProductJournal<T>(_ change: (inout ProductJournal) throws -> T) throws -> T {
        try locked {
            var state = try readLocalFile("product-changes.json", fallback: ProductJournal())
            let result = try change(&state)
            try writeLocalFile(state, name: "product-changes.json")
            return result
        }
    }
    @discardableResult public func updateWorkbench<T>(_ change: (inout Workbench) throws -> T) throws -> T {
        try locked {
            var state = try readLocalFile("workbench.json", fallback: Workbench())
            let result = try change(&state)
            try writeLocalFile(state, name: "workbench.json")
            return result
        }
    }
    func readLocalFile<T: Decodable>(_ name: String, fallback: T) throws -> T {
        let file = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: file.path) else { return fallback }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: file))
    }
    func writeLocalFile<T: Encodable>(_ state: T, name: String) throws {
        let file = directory.appendingPathComponent(name)
        try JSONEncoder.pretty.encode(state).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    @discardableResult public func update<T>(_ change: (inout Workspace) throws -> T) throws -> T {
        try locked {
            var state = try readUnlocked()
            let result = try change(&state)
            state.activities = Array(state.activities.suffix(500))
            let file = directory.appendingPathComponent("workspace.json")
            try JSONEncoder.pretty.encode(state).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            return result
        }
    }
    private func readUnlocked() throws -> Workspace {
        let file = directory.appendingPathComponent("workspace.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return Workspace() }
        return try JSONDecoder().decode(Workspace.self, from: Data(contentsOf: file))
    }
    func locked<T>(_ body: () throws -> T) throws -> T {
        localLock.lock(); defer { localLock.unlock() }
        let fd = open(directory.appendingPathComponent("workspace.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw ShopdeckError.message("Der lokale Arbeitsbereich lässt sich nicht öffnen.") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw ShopdeckError.message("Der Arbeitsbereich wird gerade verwendet.") }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
    public func addDemoShops() throws {
        try update { state in
            guard !state.shops.contains(where: \.isDemo) else { return }
            state.shops += DemoData.shops
            state.activities.append(Activity(title: "Demo gestartet", detail: "Drei Beispielshops mit fiktiven Daten sind bereit."))
        }
    }
}

public protocol CredentialStorage: Sendable {
    func load(for shopID: UUID) throws -> Credentials
    func save(_ credentials: Credentials, for shopID: UUID) throws
    func delete(for shopID: UUID) throws
}
public struct KeychainStore: CredentialStorage {
    private var interactive: Bool
    public init(interactive: Bool = false) { self.interactive = interactive }
    private struct Reply: Decodable { var status: Int32; var credentials: Credentials? }
    private var helper: URL? {
        let candidates = [Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/shopdeck-keychain"), URL(fileURLWithPath:CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("shopdeck-keychain"), FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Shopdeck/bin/shopdeck-keychain")]
        return candidates.first { FileManager.default.isExecutableFile(atPath:$0.path) }
    }
    private func run(_ command:String, id:UUID, input:Data?=nil) throws -> Reply {
        guard let helper else { throw ShopdeckError.message("Der Schlüsselbundhelfer fehlt. Öffne die aktuelle Shopdeck App.") }
        let process=Process(),output=Pipe(),stdin=Pipe()
        process.executableURL=helper;process.arguments=[command,id.uuidString];process.standardOutput=output;process.standardError=FileHandle.nullDevice;process.standardInput=stdin
        try process.run()
        if let input {stdin.fileHandleForWriting.write(input)}
        try? stdin.fileHandleForWriting.close()
        DispatchQueue.global().asyncAfter(deadline:.now()+(command=="authorize" ? 300:8)){if process.isRunning{process.terminate()}}
        let data=output.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
        guard let reply=try? JSONDecoder().decode(Reply.self,from:data) else{throw ShopdeckError.message("Der Schlüsselbundzugriff wurde beendet. Öffne die Shopeinstellungen und speichere die API Verbindung erneut.")}
        guard reply.status==errSecSuccess else{throw ShopdeckError.message(reply.status==errSecItemNotFound ? "Für diesen Shop fehlen die API Zugangsdaten. Öffne die Shopeinstellungen." : "Der Schlüsselbundzugriff ist nicht freigegeben (\(reply.status)). Öffne am Shop die Aktion Schlüsselbundzugriff freigeben oder speichere die API Verbindung erneut.")}
        return reply
    }
    public func load(for shopID:UUID) throws -> Credentials { guard let credentials=try run(interactive ? "authorize":"load",id:shopID).credentials else{throw ShopdeckError.message("Der Schlüsselbund hat keine Zugangsdaten geliefert.")};return credentials }
    public func save(_ credentials:Credentials,for shopID:UUID) throws { _ = try run("save",id:shopID,input:JSONEncoder().encode(credentials)) }
    public func delete(for shopID:UUID) throws { _ = try run("delete",id:shopID) }
}
