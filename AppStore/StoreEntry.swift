import SwiftUI
import ShopdeckCore

/// A Store client can launch this app executable with --mcp-stdio. The executable
/// carries the containing app's sandbox and profile rather than inheriting Codex's.
@main enum ShopdeckStoreEntry {
    @MainActor static func main() async {
        if CommandLine.arguments.contains("--mcp-stdio") {
            do { try await MCPStdio.run() }
            catch {
                FileHandle.standardError.write(Data("Shopdeck: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        } else {
            ShopdeckApp.main()
        }
    }
}
