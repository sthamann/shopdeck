import Foundation

/// Shared transport for the standalone server and the signed app's Store entry point.
public enum MCPStdio {
    public static func run(directory: URL? = nil) async throws {
        let store = try WorkspaceStore(directory: directory)
        let server = MCPServer(store: store, client: ShopwareClient(store: store))
        while let line = readLine() {
            guard line.utf8.count <= 1_048_576 else { continue }
            let response: JSONValue?
            do {
                response = await server.handle(try JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)))
            } catch {
                response = .object(["jsonrpc": .string("2.0"), "id": .null,
                    "error": .object(["code": .number(-32700), "message": .string("Parse error")])])
            }
            if let response {
                FileHandle.standardOutput.write(try JSONEncoder().encode(response))
                FileHandle.standardOutput.write(Data([10]))
            }
        }
    }
}
