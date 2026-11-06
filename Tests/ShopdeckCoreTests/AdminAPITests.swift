import XCTest
@testable import ShopdeckCore
final class AdminAPITests:XCTestCase {
    func testRelativePathsAndReadClassification()throws {
        XCTAssertEqual(try AdminAPIRequest(method:"get",path:"/api/product/").validated().path,"product")
        for path in ["https://example.com/api/customer","../oauth/token","product/%2e%2e/oauth/token","%252e%252e/customer","product//x","oauth/token","_mcp","product?x=1"] {XCTAssertThrowsError(try AdminAPIRequest(method:"GET",path:path).validated(),path)}
        XCTAssertTrue(try AdminAPIRequest(method:"POST",path:"search/product").validated().isReadOnly)
        XCTAssertFalse(try AdminAPIRequest(method:"POST",path:"_action/sync").validated().isReadOnly)
        XCTAssertFalse(AdminAPIRequest(method:"DELETE",path:"product/id").isReadOnly)
    }
    func testSecretsAreNeverReturned() {
        let input:JSONValue = .object(["clientSecret":.string("secret"),"nested":.array([.object(["email":.string("test@example.com"),"password":.string("secret")])])])
        let scrubbed=MCPDataProtection.scrub(input,personalData:false)
        XCTAssertFalse(scrubbed.pretty.contains("test@example.com"));XCTAssertFalse(scrubbed.pretty.contains("secret"))
        XCTAssertTrue(MCPDataProtection.scrub(input,personalData:true).pretty.contains("test@example.com"))
    }
    func testGeneralWriteIsQueuedAndScoped()async throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:dir)}
        let store=try WorkspaceStore(directory:dir);try store.addDemoShops();let shop=try store.read().shops[0]
        let server=MCPServer(store:store,client:ShopwareClient(store:store))
        func call(_ name:String,_ args:JSONValue)->JSONValue{.object(["jsonrpc":.string("2.0"),"id":.number(1),"method":.string("tools/call"),"params":.object(["_meta":.object(["io.modelcontextprotocol/protocolVersion":.string("2026-07-28")]),"name":.string(name),"arguments":args])])}
        let args:JSONValue = .object(["shop_id":.string(shop.id.uuidString),"method":.string("DELETE"),"path":.string("product/abc"),"reason":.string("Test")])
        let direct=await server.handle(call("admin_api_request",args));XCTAssertEqual(direct?["result"]["isError"].bool,true)
        let proposed=await server.handle(call("propose_admin_api_request",args));XCTAssertEqual(proposed?["result"]["isError"].bool,false)
        let queue=try store.readAdminAPIQueue();XCTAssertEqual(queue.proposals.count,1);XCTAssertEqual(queue.proposals[0].shopID,shop.id);XCTAssertEqual(queue.proposals[0].status,"pending")
        try store.update{$0.shops[0].mcpEnabled=false}
        let disabled=await server.handle(call("propose_admin_api_request",args));XCTAssertEqual(disabled?["result"]["isError"].bool,true);XCTAssertEqual(try store.readAdminAPIQueue().proposals.count,1)
    }
    func testInstallationStatusValidatesConfigAndSkill()throws {
        let home=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);defer{try? FileManager.default.removeItem(at:home)}
        let installer=ClientInstaller(home:home),helper=home.appendingPathComponent("bundle/shopdeck-mcp"),destination=home.appendingPathComponent("runtime/shopdeck-mcp")
        try FileManager.default.createDirectory(at:helper.deletingLastPathComponent(),withIntermediateDirectories:true)
        for file in [helper,helper.deletingLastPathComponent().appendingPathComponent("shopdeck-keychain")] {try Data("#!/bin/sh\nexit 0\n".utf8).write(to:file);try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:file.path)}
        XCTAssertFalse(installer.status(.codex,destination:destination).mcpConfigured)
        _ = try installer.install(.codex,helper:helper,destination:destination)
        XCTAssertTrue(installer.status(.codex,destination:destination).mcpConfigured);XCTAssertTrue(installer.status(.codex,destination:destination).skillInstalled)
        try FileManager.default.removeItem(at:home.appendingPathComponent(".agents/skills/shopdeck/SKILL.md"))
        XCTAssertFalse(installer.status(.codex,destination:destination).skillInstalled)
    }

}
