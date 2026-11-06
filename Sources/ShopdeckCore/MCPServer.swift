import Foundation

public actor MCPServer {
    let store: WorkspaceStore
    let client: ShopwareClient
    private var initialized = false
    public init(store: WorkspaceStore, client: ShopwareClient) { self.store = store; self.client = client }
    private static let info: JSONValue = .object(["name": .string("shopdeck"), "version": .string(AppVersion.current)])
    public func handle(_ message: JSONValue) async -> JSONValue? {
        let id = message["id"]
        guard message["jsonrpc"].string == "2.0", let method = message["method"].string else { return error(id, code: -32600, message: "Invalid JSON-RPC request") }
        if id == .null { return nil }
        let params = message["params"]
        let modern = params["_meta"]["io.modelcontextprotocol/protocolVersion"].string == "2026-07-28"
        do {
            var result: JSONValue
            switch method {
            case "initialize":
                initialized = true
                let requested = params["protocolVersion"].string ?? "2025-11-25"
                let version = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"].contains(requested) ? requested : "2025-11-25"
                result = .object(["protocolVersion": .string(version), "capabilities": .object(["tools": .object([:])]), "serverInfo": Self.info, "instructions": .string(ClientInstaller.skill)])
            case "server/discover":
                result = .object(["resultType": .string("complete"), "supportedVersions": .array([.string("2026-07-28")]), "capabilities": .object(["tools": .object([:])]), "instructions": .string(ClientInstaller.skill), "_meta": .object(["io.modelcontextprotocol/serverInfo": Self.info]), "ttlMs": .number(0), "cacheScope": .string("private")])
            case "ping": result = .object([:])
            case "tools/list":
                guard initialized || modern else { return error(id, code: -32000, message: "Initialize first") }
                result = .object(["tools": .array(Self.tools)])
            case "tools/call":
                guard initialized || modern else { return error(id, code: -32000, message: "Initialize first") }
                do {
                    let value = try await call(params["name"].string ?? "", args: params["arguments"])
                    result = .object(["content": .array([.object(["type": .string("text"), "text": .string(value.pretty)])]), "isError": .bool(false)])
                } catch {
                    result = .object(["content": .array([.object(["type": .string("text"), "text": .string(error.localizedDescription)])]), "isError": .bool(true)])
                }
            default: return error(id, code: -32601, message: "Method not found")
            }
            if modern, method != "initialize", var obj = result.object { obj["resultType"] = .string("complete"); obj["_meta"] = .object(["io.modelcontextprotocol/serverInfo": Self.info]); result = .object(obj) }
            return .object(["jsonrpc": .string("2.0"), "id": id, "result": result])
        }
    }
    private func error(_ id: JSONValue, code: Int, message: String) -> JSONValue {
        .object(["jsonrpc": .string("2.0"), "id": id, "error": .object(["code": .number(Double(code)), "message": .string(message)])])
    }
    private func shop(_ args: JSONValue) throws -> Shop {
        guard let raw = args["shop_id"].string, let id = UUID(uuidString: raw), let shop = try store.read().shops.first(where: { $0.id == id && $0.mcpEnabled }) else { throw ShopdeckError.message("Shop not found or MCP access disabled. Enable the shop in Shopdeck.") }
        return shop
    }
    private func call(_ name: String, args: JSONValue) async throws -> JSONValue {
        if name == "list_shops" {
            let shops = try store.read().shops.filter(\.mcpEnabled)
            return .array(shops.map { .object(["id": .string($0.id.uuidString), "name": .string($0.name), "environment": .string($0.environment), "demo": .bool($0.isDemo)]) })
        }
        let s = try shop(args)
        let payload: JSONValue
        switch name {
        case "admin_api_schema":payload = try await client.adminEntitySchema(s,entity:args["entity"].string)
        case "admin_api_routes":payload = try await client.adminRoutes(s,query:args["query"].string ?? "",page:Int(args["page"].number ?? 1))
        case "discover_shopware_tools":payload = .array(try await client.officialMCPTools(s))
        case "propose_media_upload", "propose_plugin_install", "propose_campaign":
            guard !s.isDemo else{throw ShopdeckError.message("File and CMS workflows require a connected shop, not demo data.")}
            let operation:AutomationOperation
            if name=="propose_campaign" {
                let paths=args["files"].array.compactMap(\.string);guard paths.count<=10 else{throw ShopdeckError.message("Use at most 10 local image files.")}
                let files=try paths.map{try store.stageFile($0)}
                var plan=try CampaignBuilder.make(args,assets:files)
                let ids=Array(Set(args["sections"].array.flatMap{$0["product_ids"].array.compactMap(\.string)}));guard ids.count<=50 else{throw ShopdeckError.message("Use at most 50 distinct products in one campaign.")}
                var extra=plan.object ?? [:]
                if !ids.isEmpty{let products=try await client.adminRequest(s,request:.init(method:"POST",path:"search/product",body:.object(["ids":.array(ids.map(JSONValue.string)),"limit":.number(Double(ids.count)),"associations":.object(["cover":.object(["associations":.object(["media":.object([:])])])])])),inheritance:true);guard products["data"].array.count==ids.count else{throw ShopdeckError.message("Some campaign products no longer exist in the selected shop.")};extra["product_previews"] = .array(products["data"].array.map{MCPProjection.project($0,fields:["id","name","productNumber","cover.media.url"])})}
                let channel=try await client.adminRequest(s,request:.init(method:"POST",path:"search/sales-channel",body:.object(["ids":.array([args["sales_channel_id"]]),"limit":.number(1)])))
                guard let channelRow=channel["data"].array.first else{throw ShopdeckError.message("The campaign sales channel was not found.")};extra["sales_channel_name"]=channelRow["name"];plan = .object(extra)
                operation=AutomationOperation(shop:s,kind:"campaign",title:args["title"].string ?? "Campaign",reason:args["reason"].string ?? "CMS campaign",payload:plan,files:files)
            }else{
                let plugin=name=="propose_plugin_install",file=try store.stageFile(args["file_path"].string ?? "",plugin:plugin)
                var plan:[String:JSONValue]=["activate":.bool(args["activate"].bool ?? false)]
                if plugin{let version=try await client.version(s);let compatible=ComposerConstraint.matches(version,requirement:file.metadata["coreConstraint"].string ?? "");guard compatible else{throw ShopdeckError.message("The package does not declare compatibility with Shopware "+version+". No upload was performed.")};plan["shopware_version"] = .string(version);plan["declared_compatible"] = .bool(true)}
                operation=AutomationOperation(shop:s,kind:plugin ? "plugin":"media",title:file.name,reason:args["reason"].string ?? "File upload",payload:.object(plan),files:[file])
            }
            try store.updateAutomationQueue{$0.operations.append(operation)}
            payload = .object(["operation_id":.string(operation.id.uuidString),"status":.string("pending_approval"),"files":.array(operation.files.map{.object(["file_reference":.string($0.id),"name":.string($0.name),"bytes":.number(Double($0.byteCount)),"sha256":.string($0.sha256),"metadata":$0.metadata])}),"plan":operation.payload,"message":.string("Files were copied into the private local approval record. Nothing was uploaded or installed. Review Shopdeck → Changes.")])
        case "list_operations":
            payload = .array(try store.readAutomationQueue().operations.filter{$0.shopID==s.id}.suffix(50).map{.object(["id":.string($0.id.uuidString),"kind":.string($0.kind),"title":.string($0.title),"status":.string($0.status),"checkpoints":MCPDataProtection.scrub(.object($0.checkpoints),personalData:s.shareCustomerData),"result":MCPDataProtection.scrub($0.result ?? .null,personalData:s.shareCustomerData),"error":$0.error.map(JSONValue.string) ?? .null])})
        case "call_shopware_tool":
            let native=args["name"].string ?? "",arguments=args["arguments"] == .null ? JSONValue.object([:]):args["arguments"]
            guard native.range(of:"^shopware-[a-z0-9-]{1,100}$",options:.regularExpression) != nil else{throw ShopdeckError.message("Choose a native Shopware tool name from discover_shopware_tools.")}
            let reads=["shopware-tool-search","shopware-toolsets-list","shopware-entity-read","shopware-entity-search","shopware-entity-schema","shopware-entity-aggregate"]
            if reads.contains(native){
                if native.hasPrefix("shopware-entity-"){guard let entity=arguments["entity"].string,entity.range(of:"^[a-z_\\-]+$",options:.regularExpression) != nil else{throw ShopdeckError.message("Native entity reads need an explicit entity argument.")};try MCPReadPolicy.validate(AdminAPIRequest(method:"POST",path:"search/"+entity.replacingOccurrences(of:"_",with:"-"),body:arguments),personalData:s.shareCustomerData)}
                let value=try await client.callOfficialMCP(s,name:native,arguments:arguments)
                payload=MCPDataProtection.native(value,personalData:s.shareCustomerData)
            }else{
                let operation=AutomationOperation(shop:s,kind:"native_mcp",title:native,reason:args["reason"].string ?? "Native Shopware tool",payload:.object(["name":.string(native),"arguments":arguments]))
                try store.updateAutomationQueue{$0.operations.append(operation)}
                payload = .object(["operation_id":.string(operation.id.uuidString),"status":.string("pending_approval"),"message":.string("Native mutations, configuration reads and toolset changes require review in Shopdeck. Not executed.")])
            }
        case "admin_api_request", "propose_admin_api_request":
            var request=try AdminAPIRequest(method:args["method"].string ?? "GET",path:args["path"].string ?? "",body:args["body"] == .null ? .object([:]):args["body"],query:(args["query"].object ?? [:]).compactMapValues(\.string)).validated()
            if name=="admin_api_request" {
                guard request.isReadOnly else{throw ShopdeckError.message("Queue writes via propose_admin_api_request for approval.")}
                try MCPReadPolicy.validate(request,personalData:s.shareCustomerData)
                if request.path.hasPrefix("search/"),var body=request.body.object{body["limit"] = .number(min(100,max(1,body["limit"]?.number ?? 25)));request.body = .object(body)}
                let data=MCPDataProtection.scrub(try await client.adminRequest(s,request:request),personalData:s.shareCustomerData)
                let entity=MCPReadPolicy.entity(request) ?? "",defaults:[String]?
                switch entity{case "product":defaults=["id","productNumber","name","stock","active","cover.media.url"];case "sales-channel":defaults=["id","name","typeId","active","domains"];case "media":defaults=["id","fileName","fileExtension","url","mimeType","fileSize"];case "cms-page":defaults=["id","name","type"];case "landing-page":defaults=["id","name","cmsPageId","active"];default:defaults=nil}
                if let defaults{let fields=try MCPProjection.fields(args["fields"] == .null ? .array(defaults.map(JSONValue.string)):args["fields"],entity:entity);if let rows=data.object?["data"]?.array{var result=data.object ?? [:];result["data"] = .array(rows.map{MCPProjection.project($0,fields:fields)});result["returned_fields"] = .array(fields.map(JSONValue.string));payload = .object(result)}else{payload=MCPProjection.project(data,fields:fields)}}else{payload=data}
            }
            else {let proposal=AdminAPIProposal(shop:s,request:request,reason:args["reason"].string ?? "MCP request");try store.updateAdminAPIQueue{$0.proposals.append(proposal)};payload = .object(["proposal_id":.string(proposal.id.uuidString),"status":.string("pending_approval"),"message":.string("Review in Shopdeck → Changes. Not executed.")])}
        case "list_admin_api_requests":payload = .array(try store.readAdminAPIQueue().proposals.filter{$0.shopID==s.id}.suffix(50).map{.object(["id":.string($0.id.uuidString),"method":.string($0.request.method),"path":.string($0.request.path),"status":.string($0.status),"response":MCPDataProtection.scrub($0.response ?? .null,personalData:s.shareCustomerData)])})
        case "shop_overview":
            let data = try await client.snapshot(s)
            payload = .object(["products": .number(Double(data.products)), "orders": .number(Double(data.orders)), "customers": .number(Double(data.customers)), "low_stock_products": .number(Double(data.lowStock))])
        case "search_products", "search_orders", "search_customers":
            let entity = name == "search_products" ? "product" : name == "search_orders" ? "order" : "customer"
            if entity == "customer" && !s.shareCustomerData { throw ShopdeckError.message("Customer data sharing is disabled for this shop. Enable it in Shopdeck's shop settings.") }
            let limit = Int(min(max(args["limit"].number ?? 25, 1), 100))
            let page = Int(min(max(args["page"].number ?? 1, 1), 100_000))
            let fields=try MCPProjection.fields(args["fields"],entity:entity)
            let sorting=args["sort"].array.map{RecordSort($0["field"].string ?? "id",ascending:$0["order"].string != "DESC")}
            let data = try await client.search(s, entity: entity, term: args["query"].string ?? "", page: page, limit: limit, lowStock: args["low_stock"].bool ?? false,sort:sorting.isEmpty ? nil:sorting,compact:args["fields"] == .null)
            let rows = entity == "order" && !s.shareCustomerData ? data.rows.map(Self.redactedOrder) : data.rows
            payload = .object(["data": .array(rows.map{MCPProjection.project(MCPDataProtection.scrub($0,personalData:s.shareCustomerData),fields:fields)}), "fields":.array(fields.map(JSONValue.string)),"total": .number(Double(data.total)), "page": .number(Double(page)), "limit": .number(Double(limit))])
        case "get_product", "get_order":
            let entity = name == "get_product" ? "product" : "order"
            let data = try await client.detail(s, entity: entity, id: args["id"].string ?? "")
            payload = MCPProjection.project(MCPDataProtection.scrub(entity == "order" && !s.shareCustomerData ? Self.redactedOrder(data):data,personalData:s.shareCustomerData),fields:try MCPProjection.fields(args["fields"],entity:entity,detail:true))
        case "propose_product_change":
            let id = try Validation.entityID(args["product_id"].string ?? "")
            let changes = try Validation.productChanges(args["changes"].object ?? [:])
            let product = try await client.detail(s, entity: "product", id: id)
            var proposal = ChangeProposal(shopID: s.id, productID: id, productName: product.at("name").string ?? id, changes: changes, reason: String((args["reason"].string ?? "MCP proposal").prefix(2000)))
            proposal.expectedBefore=Dictionary(uniqueKeysWithValues:changes.keys.map{($0,product[$0])})
            if let existing=try store.read().proposals.first(where:{$0.shopID==s.id && $0.productID==id && $0.status=="pending" && $0.changes==changes}){return .object(["shop":.string(s.name),"demo":.bool(s.isDemo),"result":.object(["proposal_id":.string(existing.id.uuidString),"status":.string("pending_approval"),"duplicate_prevented":.bool(true)])])}
            try store.update { state in
                guard state.shops.contains(where: { $0.id == s.id && $0.mcpEnabled }) else { throw ShopdeckError.message("MCP access was disabled.") }
                state.proposals.append(proposal)
                state.activities.append(Activity(shopID: s.id, title: "KI Änderungsvorschlag", detail: proposal.productName))
            }
            payload = .object(["proposal_id": .string(proposal.id.uuidString), "status": .string("pending_approval"), "message": .string("Open Shopdeck → Changes to review. No shop data has been changed.")])
        case "list_change_proposals":
            payload = .array(try store.read().proposals.filter { $0.shopID == s.id }.suffix(50).map { .object(["id": .string($0.id.uuidString), "product": .string($0.productName), "status": .string($0.status), "changes": .object($0.changes)]) })
        default: throw ShopdeckError.message("Unknown tool")
        }
        return .object(["shop": .string(s.name), "demo": .bool(s.isDemo), "result": payload])
    }
    static func redactedOrder(_ row: JSONValue) -> JSONValue {
        let allowed = ["id", "orderNumber", "amountTotal", "shippingTotal", "amountNet", "orderDateTime", "stateMachineState", "currency", "currencyId", "salesChannelId", "salesChannel", "lineItems"]
        var result = (row.object ?? [:]).filter { allowed.contains($0.key) }
        // Use a whitelist within line items too; payloads and custom fields may contain PII.
        if let items = result["lineItems"] { result["lineItems"] = .array(items.array.map { item in .object((item.object ?? [:]).filter { ["id", "label", "quantity", "totalPrice", "unitPrice"].contains($0.key) }) }) }
        return .object(result)
    }
    public static var tools: [JSONValue] {
        let shop: JSONValue = .object(["type": .string("string"), "description": .string("Shop UUID returned by list_shops")])
        let text: JSONValue = .object(["type": .string("string")])
        func tool(_ name: String, _ description: String, _ properties: [String: JSONValue], _ required: [String], proposal: Bool = false) -> JSONValue {
            .object(["name": .string(name), "description": .string(description), "inputSchema": .object(["type": .string("object"), "properties": .object(properties), "required": .array(required.map(JSONValue.string)), "additionalProperties": .bool(false)]), "annotations": .object(["readOnlyHint": .bool(!proposal), "destructiveHint": .bool(false), "idempotentHint": .bool(!proposal), "openWorldHint": .bool(true)])])
        }
        let fieldSelection:JSONValue = .object(["type":.string("array"),"items":text,"minItems":.number(1),"maxItems":.number(24),"description":.string("Field paths to return. Defaults are compact summaries; request detail fields explicitly. Dotted paths are returned as dotted keys.")])
        let sorting:JSONValue = .object(["type":.string("array"),"maxItems":.number(3),"items":.object(["type":.string("object"),"properties":.object(["field":text,"order":.object(["type":.string("string"),"enum":.array([.string("ASC"),.string("DESC")])])]),"required":.array([.string("field"),.string("order")]),"additionalProperties":.bool(false)])])
        var all = [tool("list_shops", "List shops explicitly enabled for MCP. Does not expose URLs or credentials.", [:], []), tool("shop_overview", "Exact catalog, order, customer and low stock counts.", ["shop_id": shop], ["shop_id"])]
        for entity in ["products", "orders", "customers"] {
            all.append(tool("search_\(entity)", "Search \(entity) on the server with pagination and sorting. Compact default fields avoid large responses; request extra fields explicitly. Customer sharing is required for personal data.", ["shop_id": shop, "query": text, "page": .object(["type": .string("integer"), "minimum": .number(1)]), "limit": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(100)]), "low_stock": .object(["type": .string("boolean")]),"fields":fieldSelection,"sort":sorting], ["shop_id"]))
        }
        for entity in ["product", "order"] { all.append(tool("get_\(entity)", "Get one \(entity) by its Shopware ID.", ["shop_id": shop, "id": text,"fields":fieldSelection], ["shop_id", "id"])) }
        let changes: JSONValue = .object(["type": .string("object"), "properties": .object(["name": text, "description": text, "stock": .object(["type": .string("integer"), "minimum": .number(0)]), "active": .object(["type": .string("boolean")])]), "additionalProperties": .bool(false), "minProperties": .number(1)])
        all.append(tool("propose_product_change", "Queue a product edit for human approval in Shopdeck. Cannot apply or approve edits.", ["shop_id": shop, "product_id": text, "changes": changes, "reason": text], ["shop_id", "product_id", "changes", "reason"], proposal: true))
        all.append(tool("list_change_proposals", "Read queued and resolved product edit proposals.", ["shop_id": shop], ["shop_id"]))
        all.append(tool("admin_api_schema","Discover every Admin API entity or retrieve one entity's fields. Available fields depend on the connected Shopware version.",["shop_id":shop,"entity":text],["shop_id"]))
        all.append(tool("admin_api_routes","Discover routes and request schemas advertised in the shop's OpenAPI document. Some extension lifecycle actions are omitted there; use propose_plugin_install for the explicit plugin workflow. Page size 50.",["shop_id":shop,"query":text,"page":.object(["type":.string("integer"),"minimum":.number(1)])],["shop_id"]))
        let requestProperties:[String:JSONValue]=["shop_id":shop,"method":text,"path":text,"body":.object(["type":.string("object")]),"query":.object(["type":.string("object"),"additionalProperties":.object(["type":.string("string")])]),"reason":text,"fields":fieldSelection]
        all.append(tool("admin_api_request","Read ANY Admin API endpoint via GET/HEAD, or DAL search/aggregate via POST. Relative paths only; integration ACL applies. Writes require propose_admin_api_request. Non-personal catalogue, CMS, media and sales channel reads do not require customer sharing. Personal entities and associations do. Secrets are always redacted. Keep search limit ≤100 and paginate.",requestProperties,["shop_id","method","path"]))
        all.append(tool("propose_admin_api_request","Queue ANY Admin API operation, including action endpoints, create/update/delete and system configuration. Requires human review in Shopdeck. This tool NEVER executes it.",requestProperties,["shop_id","method","path","reason"],proposal:true))
        all.append(tool("list_admin_api_requests","Read pending and resolved general Admin API requests for one explicit shop.",["shop_id":shop],["shop_id"]))
        all.append(tool("discover_shopware_tools","Discover the official Shopware MCP capability catalog. Falls back to the advertised session tool list on older shops; permissions and progressive discovery can restrict that list.",["shop_id":shop],["shop_id"]))
        all += AutomationToolSchemas.tools(shop:shop,text:text)
        return all
    }
}
