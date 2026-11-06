import Foundation
import ShopdeckCore

@main struct ShopdeckMCP {
    static func main() async {
        do {
            var directory: URL?
            if let index = CommandLine.arguments.firstIndex(of: "--workspace"), CommandLine.arguments.count > index + 1 { directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true) }
            let store = try WorkspaceStore(directory: directory)
            let server = MCPServer(store: store, client: ShopwareClient(store: store))
            while let line = readLine() {
                guard line.utf8.count <= 1_048_576 else { continue }
                let response: JSONValue?
                do { response = await server.handle(try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8))) }
                catch { response = .object(["jsonrpc": .string("2.0"), "id": .null, "error": .object(["code": .number(-32700), "message": .string("Parse error")])]) }
                if let response { let data = try JSONEncoder().encode(response); FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data([10])) }
            }
        } catch { FileHandle.standardError.write(Data("Shopdeck: \(error.localizedDescription)\n".utf8)); exit(1) }
    }
}
