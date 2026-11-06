import SwiftUI
import Observation
import ShopdeckCore
import UserNotifications

enum Destination: String, CaseIterable, Identifiable {
    case overview, admin, frontends, products, orders, customers, followups, changes, history, notifications, updates, ai, activity
    var id: String { rawValue }
    var title: String { switch self { case .overview: return T("Übersicht"); case .admin: return T("Administration"); case .frontends:return T("Storefronts");case .products: return T("Produkte"); case .orders: return T("Bestellungen"); case .customers: return T("Kunden"); case .followups: return T("Wiedervorlagen"); case .changes: return T("Änderungen"); case .history: return T("Änderungsverlauf"); case .notifications: return T("Benachrichtigungen"); case .updates: return "Shopware Updates"; case .ai: return "Codex & Claude"; case .activity: return T("Aktivität") } }
    var icon: String { switch self { case .overview: return "square.grid.2x2"; case .admin: return "macwindow"; case .frontends:return "globe";case .products: return "shippingbox"; case .orders: return "bag"; case .customers: return "person.2"; case .followups: return "bookmark.circle"; case .changes: return "checkmark.seal"; case .history: return "arrow.uturn.backward.circle"; case .notifications: return "bell.badge"; case .updates: return "arrow.down.circle"; case .ai: return "sparkles"; case .activity: return "clock.arrow.circlepath" } }
    var entity: String { switch self { case .orders: return "order"; case .customers: return "customer"; default: return "product" } }
}
struct ShopRecord: Identifiable, Equatable {
    let shop: Shop
    let data: JSONValue
    let entity: String
    init(shop: Shop, data: JSONValue, entity: String? = nil) { self.shop = shop; self.data = data; self.entity = entity ?? (data["orderNumber"].string != nil ? "order" : data["customerNumber"].string != nil ? "customer" : "product") }
    var id: String { shop.id.uuidString + (data["id"].string ?? "") }
    var shopName: String { shop.name }
    var sortTitle: String { data["name"].string ?? data["orderNumber"].string ?? ((data["lastName"].string ?? "") + (data["firstName"].string ?? "")) }
    var sortNumber: Double { data["stock"].number ?? data["amountTotal"].number ?? Double(data["customerNumber"].string ?? "") ?? 0 }
    var sortStatus: String { data["stateMachineState"]["technicalName"].string ?? (data["active"].bool == true ? "active" : "inactive") }
}

@MainActor @Observable final class AppModel {
    let store: WorkspaceStore
    let client: ShopwareClient
    let changeService: ProductChangeService
    let adminBrowsers = AdminBrowserStore()
    var workspace = Workspace()
    var workbench = Workbench()
    var journal = ProductJournal()
    var adminQueue = AdminAPIQueue()
    var automationQueue=AutomationQueue()
    var isChangingProducts = false
    var changeFailure:String?
    var destination: Destination = .overview {
        didSet { if oldValue != destination { query = ""; lowStockOnly = false; statusFilter = "all"; activeFilters = [];recordSort=RecordSort.defaults(destination.entity);listShopIDs=nil;listCurrency=nil;listChannelKey=nil; page = 1 } }
    }
    var selectedShopID: UUID? {didSet{if oldValue != selectedShopID{listShopIDs=nil;listChannelKey=nil;dashboardChannelKey=nil;page=1}}}
    var snapshots: [UUID: ShopSnapshot] = [:]
    var connectionErrors: [UUID: String] = [:]
    var analytics = CommerceAnalytics()
    var salesChannels:[UUID:[CommerceSalesChannel]] = [:]
    var channelLoadedAt:[UUID:Date]=[:]
    var salesChannelErrors:[UUID:String] = [:]
    var dashboardChannelKey:String?
    var listShopIDs:Set<UUID>?
    var listChannelKey:String?
    var listCurrency:String?
    var frontendURL:URL?
    var securityStatus:[UUID:SecurityPluginStatus] = [:]
    var focusSnapshot = MerchantFocusSnapshot(key: "")
    var loadingFocus = false
    var focusLoadingKey = ""
    var focusGeneration = UUID()
    var focusLoadTask: Task<MerchantFocusSnapshot, Never>?
    var loadingAnalytics = false
    var dashboardCurrency = "EUR"
    var isRefreshing = false
    var isLoading = false
    var query = ""
    var lowStockOnly = false
    var statusFilter = "all"
    var activeFilters: [RecordFilter] = []
    var showingCommandPalette = false
    var records: [ShopRecord] = []
    var recordTotal = 0
    var recordHasNext=false
    var recordCapped=false
    var recordFetched=0
    var recordSort:[RecordSort]=[]
    private var recordLoadTask:Task<FederatedSearchPage,Error>?
    var page = 1
    var error: String?
    var notice: String?
    var startWithLocalShop = false
    var showingAddShop = false
    var editShop: Shop?
    var editingRecord: ShopRecord?
    var showGroupSheet = false
    var versions: [UUID: String] = [:]
    var versionErrors: [UUID: String] = [:]
    var latestVersion: String?
    var releaseURL: URL?
    var releaseNotes = ""
    var checkingUpdates = false
    var checkingSecurity = false
    var lastUpdateCheck: Date?
    var lastUpdateAttempt: Date?
    var updateError: String?
    var clock = Date()
    var reminderIssue: String?
    var preservingRestoredPage = false
    var restoredQuery: String?
    var notificationPermission = ""
    private var preparedLocalTest = false
    private var reloadStamp = ""
    var polling = false
    private var recordGeneration = UUID()
    private var monitorTask: Task<Void, Never>?
    init() {
        let requested: URL?
        if let i = CommandLine.arguments.firstIndex(of: "--workspace"), CommandLine.arguments.count > i + 1 { requested = URL(fileURLWithPath: CommandLine.arguments[i + 1]) } else { requested = nil }
        do { store = try WorkspaceStore(directory: requested) }
        catch { fatalError("Cannot create Shopdeck application support directory: \(error)") }
        let api = ShopwareClient(store: store)
        client = api; changeService = ProductChangeService(store: store, gateway: api)
        do { if CommandLine.arguments.contains("--demo") { try store.addDemoShops() }; workspace = try store.read(); workbench = try store.readWorkbench(); journal = try store.readProductJournal();adminQueue=try store.readAdminAPIQueue();automationQueue=try store.readAutomationQueue() }
        catch { self.error = error.localizedDescription }
        let destination=store.directory.appendingPathComponent("bin/shopdeck-mcp")
        if FileManager.default.isExecutableFile(atPath:destination.path) {
            do {try ClientInstaller().updateRuntime(helper:Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/shopdeck-mcp"),destination:destination)} catch {self.error=error.localizedDescription}
        }
    }
    var scopedShops: [Shop] { workspace.shops.filter { selectedShopID == nil || $0.id == selectedShopID } }
    var selectedShop: Shop? { workspace.shops.first { $0.id == selectedShopID } }
    var pendingCount: Int { workspace.proposals.filter { $0.status == "pending" }.count + adminQueue.proposals.filter{$0.status=="pending"}.count + automationQueue.operations.filter{$0.status=="pending"}.count }
    var isDemo: Bool { !scopedShops.isEmpty && scopedShops.allSatisfy(\.isDemo) }
    func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.pollOrders(); await self.checkUpdatesIfNeeded()
                try? await Task.sleep(for: .seconds(max(30, UserDefaults.standard.double(forKey: "orderPollInterval") == 0 ? 60 : UserDefaults.standard.double(forKey: "orderPollInterval"))))
            }
        }
    }
    func reload() {
        let stamp=["workspace.json","workbench.json","product-changes.json","admin-api-requests.json","automation-operations.json"].map { name in let values=try? store.directory.appendingPathComponent(name).resourceValues(forKeys:[.contentModificationDateKey,.fileSizeKey]);return "\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0):\(values?.fileSize ?? 0)" }.joined(separator:"|")
        guard stamp != reloadStamp else{return}
        do { workspace=try store.read();workbench=try store.readWorkbench();journal=try store.readProductJournal();adminQueue=try store.readAdminAPIQueue();automationQueue=try store.readAutomationQueue();reloadStamp=stamp } catch {self.error=error.localizedDescription}
    }
    func mutate(_ change: (inout Workspace) throws -> Void) { do { try store.update(change); reload() } catch { self.error = error.localizedDescription } }
    func addDemo() async { do { try store.addDemoShops(); reload(); await refresh() } catch { self.error = error.localizedDescription } }
    func refresh() async {
        guard !isRefreshing else { return }; isRefreshing = true; defer { isRefreshing = false }
        reload()
        let shops = scopedShops
        await withTaskGroup(of: (UUID, ShopSnapshot?, String?).self) { group in
            for shop in shops { group.addTask { [client] in
                do { return (shop.id, try await client.snapshot(shop), nil) } catch { return (shop.id, nil, error.localizedDescription) }
            } }
            for await (id, snapshot, error) in group { snapshots[id] = snapshot; connectionErrors[id] = error }
        }
        if [.products, .orders, .customers].contains(destination) { await loadRecords() }
        if destination == .overview { async let stats: () = loadAnalytics(); async let focus: () = loadMerchantFocus(force: true); _ = await (stats, focus) }
    }
    func loadRecords() async {
        guard [.products,.orders,.customers].contains(destination)else{return}
        recordLoadTask?.cancel()
        let generation=UUID();recordGeneration=generation;isLoading=true
        let entity=destination.entity,term=query,requestedPage=page,low=lowStockOnly && destination == .products,status=statusFilter,sort=recordSort
        let configured=UserDefaults.standard.integer(forKey:"pageSize"),limit=UserDefaults.standard.integer(forKey:"maxServerRecords")
        let size=configured==0 ? 50:configured,maximum=limit==0 ? 1000:limit
        let channel: CommerceChannelReference?
        do { channel = try CommerceChannelReference.resolve(listChannelKey) }
        catch { records=[]; recordTotal=0; recordHasNext=false; isLoading=false; self.error=error.localizedDescription; return }
        let shops=scopedShops.filter{(listShopIDs?.contains($0.id) ?? true) && (channel==nil || $0.id==channel!.shopID)}
        var filters:[UUID:[RecordFilter]]=[:]
        for shop in shops {var values=activeFilters;if let channel{values.append(.init(name:"Sales channel",field:entity=="product" ? "visibilities.salesChannelId":"salesChannelId",value:channel.id))};if entity=="order",let code=listCurrency{values.append(.init(name:"Currency",field:"currency.isoCode",value:code))};filters[shop.id]=values}
        let task=Task{[client,filters] in try await client.searchAcrossShops(shops,entity:entity,term:term,page:requestedPage,pageSize:size,maximum:maximum,sort:sort,lowStock:low,status:status,filters:filters)};recordLoadTask=task
        do {let result=try await task.value;guard generation==recordGeneration else{return};records=result.rows.map{ShopRecord(shop:$0.shop,data:$0.data,entity:entity)};recordTotal=result.total;recordHasNext=result.hasNext;recordCapped=result.capped;recordFetched=result.fetched;if !result.failures.isEmpty{error=result.failures.joined(separator:"\n")}}
        catch is CancellationError{}catch{guard generation==recordGeneration else{return};records=[];recordHasNext=false;self.error=error.localizedDescription}
        if generation==recordGeneration{isLoading=false;recordLoadTask=nil}
    }
    func sortRecords(_ value:[RecordSort]){recordSort=value;page=1;Task{await loadRecords()}}
    func saveShop(_ shop: Shop, credentials: Credentials?) async throws {
        if let credentials { try KeychainStore().save(credentials, for: shop.id) }
        try store.update { state in
            if let i = state.shops.firstIndex(where: { $0.id == shop.id }) { state.shops[i] = shop } else { state.shops.append(shop) }
            state.activities.append(Activity(shopID: shop.id, title: T("Shop gespeichert"), detail: shop.name))
        }
        await client.invalidate(shop.id);channelLoadedAt[shop.id]=nil;salesChannels[shop.id]=nil; reload(); selectedShopID = shop.id; await refresh()
    }
    func removeShop(_ shop: Shop) {
        do {
            if !shop.isDemo { try KeychainStore().delete(for: shop.id) }
            try store.update { state in state.shops.removeAll { $0.id == shop.id }; state.rules.removeAll { $0.shopID == shop.id }; state.orderCursors[shop.id.uuidString] = nil }
            if selectedShopID == shop.id { selectedShopID = nil }; reload()
        } catch { self.error = error.localizedDescription }
    }
    func moveShop(_ source: UUID, before target: UUID?, group: UUID?) {
        mutate { state in
            guard let from = state.shops.firstIndex(where: { $0.id == source }) else { return }
            var shop = state.shops.remove(at: from); shop.groupID = group
            let index = target.flatMap { t in state.shops.firstIndex { $0.id == t } } ?? state.shops.endIndex
            state.shops.insert(shop, at: index)
        }
    }
    func saveProduct(_ record: ShopRecord, changes: [String: JSONValue]) async throws {
        let result = try await changeService.apply(record.shop, id: record.data["id"].string ?? "", changes: changes, origin: "editor")
        reload()
        if let result, result.status != .applied { throw ShopdeckError.message(T("Die Änderung muss im Änderungsverlauf geprüft werden.")) }
        mutate { $0.activities.append(Activity(shopID: record.shop.id, title: T("Produkt aktualisiert"), detail: record.data["name"].string ?? "")) }
        await refresh()
    }
    @discardableResult func resolve(_ proposal: ChangeProposal, apply: Bool,reviewedBefore:[String:JSONValue]?=nil,refreshAfter:Bool=true,notify:Bool=true,origin:String="ai") async -> Bool {
        changeFailure=nil
        guard let shop = workspace.shops.first(where: { $0.id == proposal.shopID }) else { changeFailure=T("Shop nicht gefunden");if notify{error=changeFailure};return false }
        do {
            try store.update { state in
                guard let i = state.proposals.firstIndex(where: { $0.id == proposal.id }), state.proposals[i].status == "pending" else { throw ShopdeckError.message(T("Dieser Vorschlag wurde bereits bearbeitet.")) }
                state.proposals[i].status = apply ? "applying" : "rejected"
                if !apply { state.proposals[i].resolvedAt = Date() }
            }
            reload()
            if apply {
                do {
                    let result = try await changeService.apply(shop, id: proposal.productID, changes: proposal.changes, origin:origin, operationID: proposal.id,expectedBefore:reviewedBefore ?? proposal.expectedBefore)
                    reload()
                    if let result, result.status != .applied {
                        mutate { state in if let i = state.proposals.firstIndex(where: { $0.id == proposal.id }) { state.proposals[i].status = "needs_review" } }
                        throw ShopdeckError.message(T("Die Änderung muss im Änderungsverlauf geprüft werden."))
                    }
                }
                catch { mutate { state in if let i = state.proposals.firstIndex(where: { $0.id == proposal.id }), state.proposals[i].status == "applying" { state.proposals[i].status = "pending" } }; throw error }
                mutate { state in if let i = state.proposals.firstIndex(where: { $0.id == proposal.id }) { state.proposals[i].status = "applied"; state.proposals[i].resolvedAt = Date() }; state.activities.append(Activity(shopID: shop.id, title: T("Änderung übernommen"), detail: proposal.productName)) }
            }
            if refreshAfter{await refresh()}
            return true
        } catch { changeFailure=error.localizedDescription;if notify{self.error=error.localizedDescription};return false }
    }
    func checkUpdates() async {
        await checkSecurityPlugins()
        guard !checkingUpdates else { return }; checkingUpdates = true; defer { checkingUpdates = false }
        lastUpdateAttempt = Date()
        updateError = nil
        do {
            var req = URLRequest(url: URL(string: "https://api.github.com/repos/shopware/shopware/releases?per_page=50")!); req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept"); req.setValue("Shopdeck/0.1", forHTTPHeaderField: "User-Agent"); req.timeoutInterval = 25
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ShopdeckError.message(T("Release Informationen konnten nicht geladen werden.")) }
            let json = try JSONDecoder().decode(JSONValue.self, from: data)
            let releases = json.array.filter { $0["prerelease"].bool != true && $0["draft"].bool != true }.sorted { VersionComparison.isNewer($0["tag_name"].string ?? "", than: $1["tag_name"].string ?? "") }
            guard let latest = releases.first, let tag = latest["tag_name"].string else { throw ShopdeckError.message(T("Keine stabile Version gefunden.")) }
            latestVersion = tag; releaseURL = latest["html_url"].string.flatMap(URL.init(string:)); releaseNotes = latest["body"].string ?? ""; lastUpdateCheck = Date()
            for shop in workspace.shops { do { versions[shop.id] = try await client.version(shop); versionErrors[shop.id] = nil } catch { versionErrors[shop.id] = error.localizedDescription } }
        } catch { self.updateError = error.localizedDescription }
    }
    func checkUpdatesIfNeeded() async {
        guard !workspace.shops.isEmpty, UserDefaults.standard.object(forKey: "automaticUpdateChecks") as? Bool != false,
              lastUpdateAttempt == nil || Date().timeIntervalSince(lastUpdateAttempt!) > 86400 else { return }
        await checkUpdates()
    }
    func requestNotifications() async {
        do { let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]); notificationPermission = granted ? T("Mitteilungen erlaubt") : T("Mitteilungen nicht erlaubt") }
        catch { self.error = error.localizedDescription }
    }
    func notify(title: String, body: String, id: String = UUID().uuidString) async {
        let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = UserDefaults.standard.object(forKey: "notificationSound") == nil || UserDefaults.standard.bool(forKey: "notificationSound") ? .default : nil
        do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) }
        catch { self.error = error.localizedDescription }
    }
    func pollOrders() async {
        guard !polling else { return }; polling = true; defer { polling = false }; reload()
        let rules = workspace.rules.filter(\.enabled)
        for shop in workspace.shops where rules.contains(where: { $0.shopID == nil || $0.shopID == shop.id }) {
            do {
                let key = shop.id.uuidString, cursor = workspace.orderCursors[shop.id.uuidString]
                var rows: [JSONValue] = []; var reached = cursor == nil
                for page in 1...10 {
                    let result = try await client.search(shop, entity: "order", page: page, limit: 100)
                    rows += result.rows
                    if cursor == nil || result.rows.contains(where: { cursor!.seenIDs.contains($0["id"].string ?? "") }) || page * 100 >= result.total { reached = true; break }
                }
                guard reached else { throw ShopdeckError.message(T("Zu viele neue Bestellungen. Bitte prüfe den Shop direkt.")) }
                if let cursor {
                    for row in rows.reversed() where !cursor.seenIDs.contains(row["id"].string ?? "") {
                        // Only entries newer than the oldest known boundary can be new; do not notify historical rows from later pages.
                        if let boundary = rows.firstIndex(where: { cursor.seenIDs.contains($0["id"].string ?? "") }), let index = rows.firstIndex(of: row), index > boundary { continue }
                        let matching = rules.filter { $0.matches(row, shopID: shop.id) }
                        if !matching.isEmpty {
                            let number = row["orderNumber"].string ?? ""
                            await notify(title: "\(shop.name) · \(T("Neue Bestellung")) #\(number)", body: matching.map(\.name).joined(separator: ", "), id: "order-\(shop.id)-\(row["id"].string ?? number)")
                            mutate { $0.activities.append(Activity(shopID: shop.id, title: T("Neue Bestellung") + " #" + number, detail: matching.map(\.name).joined(separator: ", "))) }
                        }
                    }
                }
                let seen = Array(rows.compactMap { $0["id"].string }.prefix(1000))
                mutate { $0.orderCursors[key] = OrderCursor(seenIDs: seen) }
            } catch { connectionErrors[shop.id] = error.localizedDescription }
        }
    }
}

extension AppModel {
    func prepareLocalTestIfRequested() async {
        guard !preparedLocalTest,let index=CommandLine.arguments.firstIndex(of:"--prepare-local-test"),CommandLine.arguments.count>index+1 else{return}
        preparedLocalTest=true
        let url=CommandLine.arguments[index+1]
        guard let old=workspace.shops.first(where:{$0.url==url && !$0.isDemo}),let container=old.containerName,container.hasPrefix("shopdeck-"),["localhost","127.0.0.1"].contains(URL(string:url)?.host ?? "") else{return}
        do { if (try? KeychainStore().load(for:old.id)) != nil { return };let credentials=try await client.bootstrapLocal(old);try await saveShop(old,credentials:credentials);selectedShopID=nil;await refresh() } catch { self.error=error.localizedDescription }
    }
    func requestKeychainAccess(_ shop:Shop) async {
        do { _ = try await Task.detached {try KeychainStore(interactive:true).load(for:shop.id)}.value;await client.invalidate(shop.id);await refresh() } catch { self.error=error.localizedDescription }
    }
}
