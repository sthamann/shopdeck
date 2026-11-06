import XCTest
import Darwin
import ImageIO
import CoreGraphics
@testable import ShopdeckCore
final class MCPWorkflowTests:XCTestCase {
    func testPrivacyIsEntitySpecificAndBlocksPersonalAssociations()throws {
        for entity in ["product","cms-page","media","sales-channel","currency"]{XCTAssertNoThrow(try MCPReadPolicy.validate(.init(method:"POST",path:"search/"+entity,body:.object(["limit":.number(1)])),personalData:false))}
        for entity in ["customer","order","integration","user"]{XCTAssertThrowsError(try MCPReadPolicy.validate(.init(method:"GET",path:entity),personalData:false))}
        XCTAssertThrowsError(try MCPReadPolicy.validate(.init(method:"POST",path:"search/product",body:.object(["associations":.object(["customer":.object([:])])])),personalData:false))
        let secret=JSONValue.object(["client_secret":.string("hidden"),"secretAccessKey":.string("hidden"),"name":.string("Public product"),"email":.string("private@example.test")])
        let scrubbed=MCPDataProtection.scrub(secret,personalData:false);XCTAssertEqual(scrubbed["name"],.string("Public product"));XCTAssertFalse(scrubbed.pretty.contains("hidden"));XCTAssertFalse(scrubbed.pretty.contains("private@example.test"))
        XCTAssertFalse(MCPDataProtection.native(.object(["content":.array([.object(["type":.string("text"),"text":.string(secret.pretty)])])]),personalData:false).pretty.contains("hidden"))
    }
    func testCompactProductProjectionAndExplicitFields()throws {
        let fields=try MCPProjection.fields(.null,entity:"product")
        let product:JSONValue = .object(["id":.string("a"),"name":.string("Chair"),"description":.string(String(repeating:"Long description ",count:5000)),"cover":.object(["media":.object(["url":.string("https://example.test/chair.jpg"),"thumbnails":.array(Array(repeating:.object(["width":.number(400)]),count:1000))])])])
        let compact=MCPProjection.project(product,fields:fields);XCTAssertLessThan(compact.pretty.count,400);XCTAssertEqual(compact["cover.media.url"],.string("https://example.test/chair.jpg"));XCTAssertEqual(compact["description"],.null)
        XCTAssertNotEqual(MCPProjection.project(product,fields:try MCPProjection.fields(.array([.string("description")]),entity:"product"))["description"],.null)
    }
    func testLanguageAndLocalDefaults()throws {
        XCTAssertEqual(AppLanguage.initial(preferred:["nl-NL","en-US"]),"nl");XCTAssertEqual(AppLanguage.initial(preferred:["ja-JP","de-DE"]),"en")
        XCTAssertEqual(LocalShopSuggestion.name(existing:["Shopware Local","shopware local 2"],prefix:"Shopware Local"),"Shopware Local 3")
        let fd=socket(AF_INET,SOCK_STREAM,0);defer{close(fd)};var address=sockaddr_in();address.sin_len=UInt8(MemoryLayout<sockaddr_in>.size);address.sin_family=sa_family_t(AF_INET);address.sin_addr.s_addr=inet_addr("127.0.0.1");address.sin_port=0
        XCTAssertEqual(withUnsafePointer(to:&address){$0.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.bind(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size))}},0)
        var length=socklen_t(MemoryLayout<sockaddr_in>.size);_ = withUnsafeMutablePointer(to:&address){$0.withMemoryRebound(to:sockaddr.self,capacity:1){getsockname(fd,$0,&length)}}
        let occupied=Int(UInt16(bigEndian:address.sin_port));XCTAssertFalse(LocalShopSuggestion.available(occupied));let next=try XCTUnwrap(LocalShopSuggestion.port(reserved:[occupied+1],startingAt:occupied));XCTAssertNotEqual(next,occupied);XCTAssertNotEqual(next,occupied+1)
    }
    func testComposerCompatibilityAndCampaignValidation()throws {
        for expression in ["^6.7","~6.7.0",">=6.7 <6.8","6.7.*","~6.6.0 || ~6.7.0"]{XCTAssertTrue(ComposerConstraint.matches("6.7.16.0",requirement:expression),expression)}
        for expression in ["^6.8","~6.6.0","unknown","<6.7"]{XCTAssertFalse(ComposerConstraint.matches("6.7.16.0",requirement:expression),expression)}
        let plan=try CampaignBuilder.make(.object(["title":.string("Test"),"sales_channel_id":.string(String(repeating:"a",count:32)),"sections":.array([.object(["type":.string("text"),"text":.string("<script>test</script>")])])]),assets:[])
        XCTAssertEqual(plan["publish"],.bool(false));XCTAssertTrue(plan.pretty.contains("&lt;script&gt;"));XCTAssertThrowsError(try CampaignBuilder.make(.object([:]),assets:[]))
    }
    func testLiveMCPMediaCampaignAndPluginApproval()async throws {
        guard ProcessInfo.processInfo.environment["SHOPDECK_WORKFLOW_LIVE"]=="1" else{throw XCTSkip("Opt in against the isolated 127.0.0.1:18888 verification container.")}
        let store=try WorkspaceStore(directory:FileManager.default.temporaryDirectory.appendingPathComponent("shopdeck-workflow-"+UUID().uuidString))
        let credentials=MemoryCredentials(),client=ShopwareClient(store:store,credentials:credentials)
        var shop=Shop(name:"Workflow verification",url:"http://127.0.0.1:18888",environment:"Lokal",mcpEnabled:true);shop.containerName="shopdeck-verification-1106";shop.shareCustomerData=false
        try credentials.save(try await client.bootstrapLocal(shop),for:shop.id);try store.update{$0.shops=[shop]}
        let server=MCPServer(store:store,client:client)
        _ = await server.handle(.object(["jsonrpc":.string("2.0"),"id":.number(1),"method":.string("initialize"),"params":.object([:])]))
        func call(_ name:String,_ properties:[String:JSONValue])async throws->JSONValue{
            var args=properties;args["shop_id"] = .string(shop.id.uuidString)
            let reply=await server.handle(.object(["jsonrpc":.string("2.0"),"id":.number(2),"method":.string("tools/call"),"params":.object(["name":.string(name),"arguments":.object(args)])]))
            let result=reply?["result"] ?? .null,text=result["content"].array.first?["text"].string ?? ""
            guard result["isError"].bool != true else{throw ShopdeckError.message(text)}
            return try JSONDecoder().decode(JSONValue.self,from:Data(text.utf8))["result"]
        }
        let compact=try await call("search_products",["limit":.number(16)]);XCTAssertLessThan(compact.pretty.count,12000);XCTAssertGreaterThan(compact["data"].array.count,0)
        let channels=try await call("admin_api_request",["method":.string("POST"),"path":.string("search/sales-channel"),"body":.object(["limit":.number(5),"filter":.array([.object(["type":.string("equals"),"field":.string("typeId"),"value":.string("8a243080f92e4c719546314b577cf82b")])])])]);let channel=try XCTUnwrap(channels["data"].array.first?["id"].string)
        let image=store.directory.appendingPathComponent("campaign.png")
        let color=CGColorSpaceCreateDeviceRGB(),context=CGContext(data:nil,width:320,height:180,bitsPerComponent:8,bytesPerRow:1280,space:color,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red:0,green:0.5,blue:1,alpha:1));context.fill(CGRect(x:0,y:0,width:320,height:180));let dest=CGImageDestinationCreateWithURL(image as CFURL,"public.png" as CFString,1,nil)!;CGImageDestinationAddImage(dest,context.makeImage()!,nil);XCTAssertTrue(CGImageDestinationFinalize(dest))
        let service=AutomationService(store:store,client:client)
        var pluginName:String?
        func cleanup()async {
            let queue=(try? store.readAutomationQueue())?.operations ?? []
            for operation in queue{if let id=operation.payload["landing_page_id"].string{_ = try? await client.adminRequest(shop,request:.init(method:"DELETE",path:"landing-page/"+id))};if let id=operation.payload["page"]["id"].string{_ = try? await client.adminRequest(shop,request:.init(method:"DELETE",path:"cms-page/"+id))};for (key,value) in operation.checkpoints where key.hasPrefix("media:"){if let id=value["id"].string{_ = try? await client.adminRequest(shop,request:.init(method:"DELETE",path:"media/"+id))}}}
            if let name=pluginName{_ = try? await client.adminRequest(shop,request:.init(method:"PUT",path:"_action/extension/deactivate/plugin/"+name));_ = try? await client.adminRequest(shop,request:.init(method:"POST",path:"_action/extension/uninstall/plugin/"+name));_ = try? await client.adminRequest(shop,request:.init(method:"POST",path:"_action/extension/remove/plugin/"+name))}
        }
        do{
            let proposal=try await call("propose_media_upload",["file_path":.string(image.path),"reason":.string("Isolated regression test")]);let id=try XCTUnwrap(UUID(uuidString:proposal["operation_id"].string ?? ""))
            XCTAssertEqual(try store.readAutomationQueue().operations.first?.status,"pending");XCTAssertTrue(try store.readAutomationQueue().operations.first?.checkpoints.isEmpty==true)
            let uploaded=try await service.execute(id,shop:shop);XCTAssertEqual(uploaded.status,"applied");XCTAssertEqual(uploaded.result?["verified"],.bool(true));print("Live workflow: media binary upload and readback verified")
            let campaign=try await call("propose_campaign",["title":.string("Shopdeck isolated workflow test"),"sales_channel_id":.string(channel),"publish":.bool(true),"files":.array([.string(image.path)]),"sections":.array([.object(["type":.string("text"),"text":.string("Shopdeck workflow verification")]),.object(["type":.string("image"),"file_index":.number(0)]),.object(["type":.string("product_slider"),"product_ids":.array(compact["data"].array.prefix(4).map{$0["id"]})])]),"reason":.string("Isolated campaign verification")])
            let campaignID=try XCTUnwrap(UUID(uuidString:campaign["operation_id"].string ?? "")),created=try await service.execute(campaignID,shop:shop)
            XCTAssertEqual(created.result?["stored_content_verified"],.bool(true));XCTAssertEqual(created.result?["storefront_verified"],.bool(true));print("Live workflow: CMS text, image and four products stored and storefront reachable")
            let name="ShopdeckVerify"+UUID().uuidString.replacingOccurrences(of:"-",with:"").prefix(8);pluginName=name
            let package=store.directory.appendingPathComponent(name);try FileManager.default.createDirectory(at:package.appendingPathComponent("src"),withIntermediateDirectories:true)
            let composer:JSONValue = .object(["name":.string("shopdeck/verification"),"description":.string("Isolated Shopdeck workflow verification plugin"),"type":.string("shopware-platform-plugin"),"version":.string("1.0.0"),"license":.string("MIT"),"require":.object(["shopware/core":.string("~6.7.0")]),"autoload":.object(["psr-4":.object([name+"\\":.string("src/")])]),"extra":.object(["shopware-plugin-class":.string(name+"\\"+name),"label":.object(["en-GB":.string("Shopdeck verification")])])])
            try JSONEncoder().encode(composer).write(to:package.appendingPathComponent("composer.json"));try Data(("<?php declare(strict_types=1); namespace "+name+"; class "+name+" extends \\Shopware\\Core\\Framework\\Plugin {}\n").utf8).write(to:package.appendingPathComponent("src/"+name+".php"))
            let zip=store.directory.appendingPathComponent("plugin.zip"),process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/zip");process.currentDirectoryURL=store.directory;process.arguments=["-qr",zip.path,name];try process.run();process.waitUntilExit();XCTAssertEqual(process.terminationStatus,0)
            let plugin=try await call("propose_plugin_install",["file_path":.string(zip.path),"activate":.bool(true),"reason":.string("Empty test plugin, removed after verification")]),pluginID=try XCTUnwrap(UUID(uuidString:plugin["operation_id"].string ?? "")),installed=try await service.execute(pluginID,shop:shop)
            XCTAssertEqual(installed.result?["active"],.bool(true));XCTAssertEqual(installed.result?["verified"],.bool(true));print("Live workflow: real plugin ZIP uploaded, installed, activated and verified")
            let official=try await call("discover_shopware_tools",[:]);XCTAssertTrue(official.array.contains{$0["availability"].string=="catalogue_only_use_discovery_or_enable_toolset"});let toolsets=try await call("call_shopware_tool",["name":.string("shopware-toolsets-list"),"arguments":.object([:])]);XCTAssertNotEqual(toolsets,.null);print("Live workflow: native MCP invocation and catalogue/session distinction verified")
            await cleanup()
        }catch{await cleanup();throw error}
    }

}
