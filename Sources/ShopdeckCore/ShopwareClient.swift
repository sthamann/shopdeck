import Foundation

final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

public actor ShopwareClient {
    private let credentials: any CredentialStorage
    private let store: WorkspaceStore
    private let session: URLSession
    private var tokens: [UUID: (token: String, expiry: Date)] = [:]
    public init(store: WorkspaceStore, credentials: any CredentialStorage = KeychainStore(), session: URLSession? = nil) {
        self.store = store; self.credentials = credentials
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25; config.timeoutIntervalForResource = 45
        self.session = session ?? URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    public func invalidate(_ shopID: UUID) { tokens[shopID] = nil }
    private func endpoint(_ shop: Shop, _ path: String) throws -> URL {
        let base = try Validation.shopURL(shop.url)
        return base.appendingPathComponent("api").appendingPathComponent(path)
    }
    private func token(_ shop: Shop, override: Credentials? = nil) async throws -> String {
        if override == nil, let cached = tokens[shop.id], cached.expiry > Date() { return cached.token }
        let c = try override ?? credentials.load(for: shop.id)
        var request = URLRequest(url: try endpoint(shop, "oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(JSONValue.object(["grant_type": .string("client_credentials"), "client_id": .string(c.clientID), "client_secret": .string(c.clientSecret)]))
        let json = try await send(request)
        guard let token = json["access_token"].string else { throw ShopdeckError.message("Der Shop hat keinen API Zugriffstoken geliefert.") }
        if override == nil { tokens[shop.id] = (token, Date().addingTimeInterval(max(0, (json["expires_in"].number ?? 600) - 60))) }
        return token
    }
    public func testConnection(_ shop: Shop, credentials: Credentials) async throws {
        if shop.isDemo { return }
        let access = try await token(shop, override: credentials)
        _ = try await request(shop, path: "search/product", body: .object(["limit": .number(1)]), access: access)
    }
    private func send(_ request: URLRequest) async throws -> JSONValue {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ShopdeckError.message("Der Shop hat keine gültige HTTP Antwort geliefert.") }
        guard (200..<300).contains(http.statusCode) else {
            let json = try? JSONDecoder().decode(JSONValue.self, from: data)
            let code = json?["errors"].array.first?["code"].string ?? ""
            let pointer = json?["errors"].array.first?["source"]["pointer"].string ?? ""
            let explanation: String
            switch http.statusCode {
            case 301...399: explanation = "Die Shopadresse leitet weiter. Trage die endgültige HTTPS Adresse ein."
            case 401: explanation = "Die API Zugangsdaten sind ungültig oder abgelaufen."
            case 403: explanation = "Der Integration fehlen die Rechte für diese Aktion."
            case 404: explanation = "Der API Endpunkt wurde nicht gefunden. Prüfe die Shopadresse und Shopware Version."
            case 429: explanation = "Der Shop erhält gerade zu viele Anfragen. Warte kurz und lade erneut."
            default: explanation = "Der Shop hat die Anfrage abgelehnt."
            }
            throw ShopdeckError.message("\(explanation) HTTP \(http.statusCode)\(code.isEmpty ? "" : " · \(code)")\(pointer.isEmpty ? "" : " · \(pointer)")")
        }
        if data.isEmpty { return .object([:]) }
        do { return try JSONDecoder().decode(JSONValue.self, from: data) }
        catch { throw ShopdeckError.message("Die Antwort ist kein gültiges Shopware JSON. Prüfe die Shopadresse.") }
    }
    private func request(_ shop: Shop, path: String, method: String = "POST", body: JSONValue, access: String? = nil, retried: Bool = false, inheritance: Bool = false, query: [String:String] = [:]) async throws -> JSONValue {
        let bearer: String
        if let access { bearer = access } else { bearer = try await token(shop) }
        var components=URLComponents(url:try endpoint(shop,path),resolvingAgainstBaseURL:false)!;if !query.isEmpty{components.queryItems=query.sorted{$0.key<$1.key}.map{URLQueryItem(name:$0.key,value:$0.value)}}
        var req = URLRequest(url: components.url!); req.httpMethod = method
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if inheritance { req.setValue("1", forHTTPHeaderField: "sw-inheritance") }
        if !["GET","HEAD"].contains(method) { req.httpBody = try JSONEncoder().encode(body) }
        do { return try await send(req) }
        catch {
            if !retried, access == nil, error.localizedDescription.contains("HTTP 401") {
                tokens[shop.id] = nil
                return try await request(shop, path: path, method: method, body: body, retried: true, inheritance: inheritance, query: query)
            }
            throw error
        }
    }
    public func search(_ shop: Shop, entity: String, term: String = "", page: Int = 1, limit: Int = 50, lowStock: Bool = false, status: String = "all", customFilters: [RecordFilter] = [], sort:[RecordSort]?=nil,compact:Bool=false) async throws -> SearchResult {
        guard ["product", "order", "customer", "sales-channel"].contains(entity) else { throw ShopdeckError.message("Diese Datenart wird nicht unterstützt.") }
        let size = min(max(limit, 1), 100), page = max(page, 1)
        let filters = try SearchFilters.criteria(entity: entity, lowStock: lowStock, status: status) + customFilters.map { try $0.criteria() }
        if shop.isDemo { return try DemoData.search(shop, entity: entity, term: term, page: page, limit: size, lowStock: lowStock, workspace: store.read(), status: status, customFilters: customFilters, sort:sort ?? RecordSort.defaults(entity)) }
        var body: [String: JSONValue] = ["limit": .number(Double(size)), "page": .number(Double(page)), "total-count-mode": .number(1)]
        if !term.isEmpty { body["term"] = .string(String(term.prefix(500))) }
        if !filters.isEmpty { body["filter"] = .array(filters) }
        if entity == "order" {
            body["sort"] = .array([.object(["field": .string("orderDateTime"), "order": .string("DESC")])])
            body["associations"] = .object(["stateMachineState": .object([:]), "currency": .object([:]), "orderCustomer": .object([:]), "salesChannel": .object([:]), "transactions": .object(["associations": .object(["stateMachineState": .object([:])])]), "deliveries": .object(["associations": .object(["stateMachineState": .object([:])])])])
        } else if entity == "product" {
            body["sort"] = .array([.object(["field": .string("name"), "order": .string("ASC")])])
            body["associations"] = .object(["cover": .object(["associations": .object(["media": .object([:])])]), "manufacturer": .object([:])])
        }
        if entity == "customer" { body["associations"] = .object(["group": .object([:]), "defaultBillingAddress": .object(["associations": .object(["country": .object([:])])])]) }
        if compact {
            let base=entity=="product" ? ["id","productNumber","name","stock","active","cover"]:entity=="order" ? ["id","orderNumber","orderDateTime","amountTotal","currency","stateMachineState","salesChannelId"]:["id","customerNumber","firstName","lastName","email","active"]
            body["includes"] = .object([entity.replacingOccurrences(of:"-",with:"_"):.array(base.map(JSONValue.string)),"product_media":.array([.string("media")]),"media":.array([.string("url")]),"currency":.array([.string("isoCode")]),"state_machine_state":.array([.string("technicalName")])])
        }
        let requestedSort=sort ?? RecordSort.defaults(entity)
        body["sort"] = .array(try requestedSort.map{try $0.criteria()})
        let result = try await request(shop, path: "search/\(entity)", body: .object(body), inheritance: entity == "product")
        return SearchResult(rows: result["data"].array, total: Int(result["total"].number ?? Double(result["data"].array.count)))
    }
    public func detail(_ shop: Shop, entity: String, id: String) async throws -> JSONValue { try await detail(shop, entity: entity, id: id, resolveInheritance: false) }
    public func detail(_ shop: Shop, entity: String, id: String, resolveInheritance: Bool) async throws -> JSONValue {
        let id = try Validation.entityID(id)
        guard ["product", "order", "customer"].contains(entity) else { throw ShopdeckError.message("Unbekannte Datenart.") }
        if shop.isDemo {
            guard let row = try DemoData.search(shop, entity: entity, term: "", page: 1, limit: 100, lowStock: false, workspace: store.read()).rows.first(where: { $0["id"].string == id }) else { throw ShopdeckError.message("Datensatz nicht gefunden.") }
            return row
        }
        var body: [String: JSONValue] = ["ids": .array([.string(id)]), "limit": .number(1)]
        let address: JSONValue = .object(["associations": .object(["country": .object([:]), "countryState": .object([:]), "salutation": .object([:])])])
        let associations: [String: JSONValue]
        switch entity {
        case "order": associations = ["lineItems": .object([:]), "currency": .object([:]), "stateMachineState": .object([:]), "orderCustomer": .object([:]), "addresses": address, "billingAddress": address, "deliveries": .object(["associations": .object(["shippingOrderAddress": address, "shippingMethod": .object([:]), "stateMachineState": .object([:])])]), "transactions": .object(["associations": .object(["paymentMethod": .object([:]), "stateMachineState": .object([:])])]), "salesChannel": .object([:])]
        case "customer": associations = ["addresses": address, "defaultBillingAddress": address, "defaultShippingAddress": address, "group": .object([:]), "salutation": .object([:]), "salesChannel": .object([:]), "tags": .object([:])]
        default: associations = ["manufacturer": .object([:]), "tax": .object([:]), "unit": .object([:]), "deliveryTime": .object([:]), "cover": .object(["associations": .object(["media": .object([:])])]), "media": .object(["associations": .object(["media": .object([:])])]), "properties": .object(["associations": .object(["group": .object([:])])]), "options": .object([:]), "categories": .object([:]), "tags": .object([:])]
        }
        body["associations"] = .object(associations)
        let result = try await request(shop, path: "search/\(entity)", body: .object(body), inheritance: resolveInheritance && entity == "product")
        guard let row = result["data"].array.first else { throw ShopdeckError.message("Datensatz nicht gefunden.") }
        return row
    }
    public func snapshot(_ shop: Shop) async throws -> ShopSnapshot {
        // The actor interleaves network waits; counts are exact API totals, never extrapolated.
        async let products = search(shop, entity: "product", limit: 1)
        async let orders = search(shop, entity: "order", limit: 8)
        async let customers = search(shop, entity: "customer", limit: 1)
        async let low = search(shop, entity: "product", limit: 1, lowStock: true)
        let (p, o, c, l) = try await (products, orders, customers, low)
        return ShopSnapshot(shop: shop, products: p.total, orders: o.total, customers: c.total, lowStock: l.total, recentOrders: o.rows)
    }
    public func updateProduct(_ shop: Shop, id: String, changes: [String: JSONValue]) async throws {
        let id = try Validation.entityID(id), validated = try Validation.productChanges(changes)
        try await writeProduct(shop, id: id, validated: validated)
    }
    public func restoreProduct(_ shop: Shop, id: String, changes: [String: JSONValue]) async throws {
        let id = try Validation.entityID(id), validated = try Validation.productRestoration(changes)
        try await writeProduct(shop, id: id, validated: validated)
    }
    private func writeProduct(_ shop: Shop, id: String, validated: [String: JSONValue]) async throws {
        if shop.isDemo {
            try store.update { state in
                let key = "\(shop.id.uuidString):\(id)"
                state.demoOverrides[key, default: [:]].merge(validated) { _, new in new }
            }
        } else { _ = try await request(shop, path: "product/\(id)", method: "PATCH", body: .object(validated)) }
    }
    public func version(_ shop: Shop) async throws -> String {
        if shop.isDemo { return "6.7.10.0" }
        let result = try await request(shop, path: "_info/version", method: "GET", body: .null)
        guard let version = result["version"].string else { throw ShopdeckError.message("Der Shop liefert keine Versionsnummer.") }
        return version
    }
    /// Bootstrap only on the loopback test container created by this app.
    public func bootstrapLocal(_ shop: Shop) async throws -> Credentials {
        guard ["localhost", "127.0.0.1"].contains(URL(string: shop.url)?.host ?? ""), shop.containerName?.hasPrefix("shopdeck-") == true else { throw ShopdeckError.message("Die automatische Einrichtung ist nur für lokale Shopdeck Testshops erlaubt.") }
        var request = URLRequest(url: try endpoint(shop, "oauth/token")); request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(JSONValue.object(["grant_type": .string("password"), "client_id": .string("administration"), "username": .string("admin"), "password": .string("shopware")]))
        let response = try await send(request)
        guard let access = response["access_token"].string else { throw ShopdeckError.message("Der lokale Adminzugang konnte nicht eingerichtet werden.") }
        let c = Credentials(clientID: "SWIA" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(28), clientSecret: UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: ""))
        let body: JSONValue = .object(["id": .string(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()), "label": .string("Shopdeck Local"), "accessKey": .string(c.clientID), "secretAccessKey": .string(c.clientSecret), "admin": .bool(true)])
        _ = try await self.request(shop, path: "integration", body: body, access: access)
        try await testConnection(shop, credentials: c)
        return c
    }
}
extension ShopwareClient: ProductGateway {}

extension ShopwareClient {
    public func adminRequest(_ shop:Shop,request input:AdminAPIRequest,inheritance:Bool=false) async throws -> JSONValue {
        let action=try input.validated()
        guard !shop.isDemo else{throw ShopdeckError.message("Die allgemeine Admin API braucht einen echten Shop.")}
        return try await request(shop,path:action.path,method:action.method,body:action.body,inheritance:inheritance,query:action.query)
    }
    public func adminEntitySchema(_ shop:Shop,entity:String?) async throws -> JSONValue {
        let schema=try await adminRequest(shop,request:.init(method:"GET",path:"_info/entity-schema.json"))
        if let entity,!entity.isEmpty {guard let value=schema.object?[entity.replacingOccurrences(of:"-",with:"_")] else{throw ShopdeckError.message("Datenart nicht im Shop Schema gefunden.")};return value}
        return .object(["entities":.array((schema.object ?? [:]).keys.sorted().map(JSONValue.string)),"count":.number(Double(schema.object?.count ?? 0))])
    }
    public func adminRoutes(_ shop:Shop,query:String="",page:Int=1) async throws -> JSONValue {
        let schema=try await adminRequest(shop,request:.init(method:"GET",path:"_info/openapi3.json"))
        var routes:[JSONValue]=[]
        for (path,value) in (schema["paths"].object ?? [:]).sorted(by:{$0.key<$1.key}) {
            for method in ["get","post","patch","put","delete","head"] {if let definition=value.object?[method],query.isEmpty || (path+" "+(definition["summary"].string ?? "")).localizedCaseInsensitiveContains(query){routes.append(.object(["path":.string(path),"method":.string(method.uppercased()),"summary":definition["summary"],"parameters":definition["parameters"],"requestBody":definition["requestBody"]]))}}
        }
        return .object(["routes":.array(Array(routes.dropFirst((max(page,1)-1)*50).prefix(50))),"total":.number(Double(routes.count)),"page":.number(Double(max(page,1)))])
    }
    public func officialMCPTools(_ shop:Shop) async throws -> [JSONValue] {
        guard !shop.isDemo else{return []}
        let available=try await nativeMCP(shop,tool:nil,arguments:.object([:]))
        let names=Set(available.array.compactMap{$0["name"].string})
        let capabilities=try? await adminRequest(shop,request:.init(method:"GET",path:"_action/mcp/capabilities"))
        let catalog=capabilities?["tools"].array ?? []
        var all=catalog
        for item in available.array where !all.contains(where:{$0["name"]==item["name"]}){all.append(item)}
        return all.map { item in var value=item.object ?? [:];let callable=names.contains(item["name"].string ?? "");value["session_available"] = .bool(callable);value["availability"] = .string(callable ? "advertised_in_current_session":"catalogue_only_use_discovery_or_enable_toolset");value["call_via"] = .string("call_shopware_tool");return .object(value) }
    }
    public func callOfficialMCP(_ shop:Shop,name:String,arguments:JSONValue) async throws -> JSONValue {try await nativeMCP(shop,tool:name,arguments:arguments)}
    private func nativeMCP(_ shop:Shop,tool:String?,arguments:JSONValue) async throws -> JSONValue {
        guard !shop.isDemo else{throw ShopdeckError.message("Official MCP needs a connected Shopware shop.")}
        let url=try endpoint(shop,"_mcp"),bearer=try await token(shop)
        var sessionID:String?
        func rpc(_ method:String,_ params:JSONValue,_ id:Int) async throws -> JSONValue {
            var request=URLRequest(url:url);request.httpMethod="POST";request.setValue("Bearer "+bearer,forHTTPHeaderField:"Authorization");request.setValue("application/json",forHTTPHeaderField:"Content-Type");request.setValue("application/json, text/event-stream",forHTTPHeaderField:"Accept");request.setValue("2025-11-25",forHTTPHeaderField:"MCP-Protocol-Version");if let sessionID{request.setValue(sessionID,forHTTPHeaderField:"Mcp-Session-Id")}
            request.httpBody=try JSONEncoder().encode(JSONValue.object(["jsonrpc":.string("2.0"),"id":.number(Double(id)),"method":.string(method),"params":params]))
            let (data,response)=try await self.session.data(for:request)
            guard let http=response as? HTTPURLResponse,(200..<300).contains(http.statusCode) else{throw ShopdeckError.message("The official Shopware MCP endpoint is unavailable or access is denied.")}
            if let value=http.value(forHTTPHeaderField:"Mcp-Session-Id"){sessionID=value}
            let reply:JSONValue
            if let json=try? JSONDecoder().decode(JSONValue.self,from:data){reply=json}
            else{let text=String(decoding:data,as:UTF8.self);guard let line=text.split(separator:"\n").last(where:{$0.hasPrefix("data: ")}),let json=try? JSONDecoder().decode(JSONValue.self,from:Data(line.dropFirst(6).utf8)) else{throw ShopdeckError.message("Invalid official MCP response.")};reply=json}
            if reply["error"] != .null{throw ShopdeckError.message("Official MCP rejected the call: "+String(reply["error"]["message"].string?.prefix(500) ?? "unknown error"))}
            return reply["result"]
        }
        _ = try await rpc("initialize",.object(["protocolVersion":.string("2025-11-25"),"capabilities":.object([:]),"clientInfo":.object(["name":.string("Shopdeck"),"version":.string(AppVersion.current)])]),1)
        var tools:[JSONValue]=[],cursor:String?,seen=Set<String>()
        for index in 0..<30{let response=try await rpc("tools/list",cursor.map{.object(["cursor":.string($0)])} ?? .object([:]),index+2);tools+=response["tools"].array;guard let next=response["nextCursor"].string,seen.insert(next).inserted else{break};cursor=next}
        guard let tool else{return .array(tools)}
        if !tools.contains(where:{$0["name"].string==tool}),tools.contains(where:{$0["name"].string=="shopware-tool-search"}){_ = try await rpc("tools/call",.object(["name":.string("shopware-tool-search"),"arguments":.object(["query":.string(tool)])]),100)}
        let result=try await rpc("tools/call",.object(["name":.string(tool),"arguments":arguments]),101)
        guard result["isError"].bool != true else{throw ShopdeckError.message("The native tool is not usable in this shop session: "+String(result["content"].array.compactMap{$0["text"].string}.joined(separator:" ").prefix(800)))}
        return result
    }
    public func orderDocuments(_ shop: Shop, orderIDs: [String]) async throws -> OrderDocumentPage {
        let ids = try Array(Set(orderIDs)).sorted().map(Validation.entityID)
        guard !ids.isEmpty, ids.count <= 200 else { throw ShopdeckError.message("Wähle zwischen einer und 200 Bestellungen.") }
        if shop.isDemo {
            let rows = try ids.map { id in try OrderDocument(shop: shop, data: .object(["id": .string(id), "orderId": .string(id), "documentType": .object(["technicalName": .string("invoice")]), "config": .object(["documentNumber": .string("DEMO-" + String(id.suffix(4)))]), "deepLinkCode": .string(String(repeating: "d", count: 32))])) }
            return .init(documents: rows, total: rows.count)
        }
        var rows: [OrderDocument] = [], total = 0
        for page in 1...10 {
            try Task.checkCancellation()
            let body: JSONValue = .object(["page": .number(Double(page)), "limit": .number(100), "total-count-mode": .number(1), "filter": .array([.object(["type": .string("equalsAny"), "field": .string("orderId"), "value": .array(ids.map(JSONValue.string))])]), "sort": .array([.object(["field": .string("createdAt"), "order": .string("DESC")]), .object(["field": .string("id"), "order": .string("ASC")])]), "associations": .object(["documentType": .object([:])])])
            let response = try await adminRequest(shop, request: .init(method: "POST", path: "search/document", body: body))
            let values = response["data"].array; total = Int(response["total"].number ?? Double(values.count))
            rows += try values.map { try OrderDocument(shop: shop, data: $0) }
            if values.isEmpty || rows.count >= total { break }
        }
        return .init(documents: rows, total: total)
    }
    public func downloadDocument(_ document: OrderDocument) async throws -> Data {
        if document.shop.isDemo { return OrderDocument.demoPDF(number: document.number) }
        let path = try document.downloadPath(), shop = document.shop
        for attempt in 0...1 {
            let delegate = DocumentDownloadDelegate()
            var request = URLRequest(url: try endpoint(shop, path)); request.httpMethod = "GET"; request.timeoutInterval = 90
            request.setValue("Bearer " + (try await token(shop)), forHTTPHeaderField: "Authorization"); request.setValue("application/pdf", forHTTPHeaderField: "Accept")
            do {
                let (file, response) = try await session.download(for: request, delegate: delegate)
                defer { try? FileManager.default.removeItem(at: file) }
                guard let http = response as? HTTPURLResponse else { throw ShopdeckError.message("Ungültige Antwort beim Dokumentdownload.") }
                if http.statusCode == 401 && attempt == 0 { tokens[shop.id] = nil; continue }
                guard http.statusCode == 200 else { throw ShopdeckError.message("Das Dokument konnte nicht geladen werden. HTTP " + String(http.statusCode) + (http.statusCode == 403 ? " · Der Integration fehlt document:read." : "")) }
                let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= delegate.maximum else { throw ShopdeckError.message("Das Dokument überschreitet 32 MB.") }
                let data = try Data(contentsOf: file, options: .mappedIfSafe)
                guard data.starts(with: Data("%PDF-".utf8)) else { throw ShopdeckError.message("Der Shop hat kein PDF Dokument geliefert.") }
                return data
            } catch { if delegate.tooLarge { throw ShopdeckError.message("Das Dokument überschreitet 32 MB.") }; throw error }
        }
        throw ShopdeckError.message("Der Dokumentzugriff ist nicht autorisiert.")
    }
    public func uploadBinary(_ shop:Shop,path:String,data:Data,contentType:String,query:[String:String]=[:])async throws->JSONValue {
        guard !shop.isDemo else{throw ShopdeckError.message("File upload needs a real shop.")}
        let clean=try AdminAPIRequest(method:"POST",path:path).validated()
        var components=URLComponents(url:try endpoint(shop,clean.path),resolvingAgainstBaseURL:false)!
        components.queryItems=query.map{URLQueryItem(name:$0.key,value:$0.value)}
        var req=URLRequest(url:components.url!);req.httpMethod="POST";req.timeoutInterval=180;req.setValue("Bearer "+(try await token(shop)),forHTTPHeaderField:"Authorization");req.setValue(contentType,forHTTPHeaderField:"Content-Type");req.setValue("application/json",forHTTPHeaderField:"Accept");req.httpBody=data
        return try await send(req)
    }
}
