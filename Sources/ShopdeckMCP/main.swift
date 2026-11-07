import Foundation
import ShopdeckCore

@main struct ShopdeckMCP {
    static func main() async {
        do {
            var directory: URL?
            if let index = CommandLine.arguments.firstIndex(of: "--workspace"), CommandLine.arguments.count > index + 1 { directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true) }
            try await MCPStdio.run(directory: directory)
        } catch { FileHandle.standardError.write(Data("Shopdeck: \(error.localizedDescription)\n".utf8)); exit(1) }
    }
}
