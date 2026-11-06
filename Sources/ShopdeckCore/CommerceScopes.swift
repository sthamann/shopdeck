import Foundation

public struct StorefrontDomain:Codable,Identifiable,Sendable,Equatable {
    public var id:String;public var url:String;public var currency:String;public var language:String
    public var safeURL:URL? {guard let value=URL(string:url),["https","http"].contains(value.scheme?.lowercased() ?? ""),value.host != nil,value.user==nil,value.password==nil else{return nil};return value}
}
public struct CommerceSalesChannel:Codable,Identifiable,Sendable,Equatable {
    public var id:String;public var shopID:UUID;public var name:String;public var active:Bool;public var type:String;public var domains:[StorefrontDomain];public var currencies:[String]
    public var key:String{shopID.uuidString+":"+id}
    public init(shopID:UUID,data:JSONValue){id=data["id"].string ?? "";self.shopID=shopID;name=data.at("name").string ?? id;active=data["active"].bool ?? false;type=data["type"]["name"].string ?? "";currencies=data["currencies"].array.compactMap{$0["isoCode"].string}.sorted();domains=data["domains"].array.compactMap{row in guard let id=row["id"].string,let url=row["url"].string else{return nil};return .init(id:id,url:url,currency:row["currency"]["isoCode"].string ?? "",language:row["language"]["locale"]["code"].string ?? "")}}
}
public struct RevenueMonth:Codable,Sendable,Equatable {
    public var shopID:UUID;public var salesChannelID:String;public var currency:String;public var month:String;public var revenue:Double;public var orders:Int
    public init(shopID:UUID,salesChannelID:String,currency:String,month:String,revenue:Double,orders:Int){self.shopID=shopID;self.salesChannelID=salesChannelID;self.currency=currency;self.month=month;self.revenue=revenue;self.orders=orders}
}
extension CommerceAnalytics {
    public func scoped(shopIDs:Set<UUID>,channelKeys:Set<String>?=nil)->Self {var copy=self;copy.orders=orders.filter{shopIDs.contains($0.shopID) && (channelKeys==nil || channelKeys!.contains($0.shopID.uuidString+":"+($0.data["salesChannelId"].string ?? "")))};copy.revenueMonths=revenueMonths.filter{shopIDs.contains($0.shopID) && (channelKeys==nil || channelKeys!.contains($0.shopID.uuidString+":"+$0.salesChannelID))};return copy}
    public func calendarRevenue(_ component:Calendar.Component,currency:String,now:Date=Date(),calendar:Calendar = .current)->Double {
        let parts=calendar.dateComponents([.year,.month],from:now),year=String(format:"%04d",parts.year!),month=String(format:"%04d-%02d",parts.year!,parts.month!)
        return revenueMonths.filter{$0.currency==currency && (component == .year ? $0.month.hasPrefix(year+"-"):$0.month==month)}.reduce(0){$0+$1.revenue}
    }
    public func monthlySeries(currency:String,now:Date=Date(),calendar:Calendar = .current)->[AnalyticsSeriesPoint] {let year=calendar.component(.year,from:now);return (1...12).map{month in let key=String(format:"%04d-%02d",year,month);let rows=revenueMonths.filter{$0.currency==currency && $0.month==key};return .init(date:calendar.date(from:DateComponents(year:year,month:month,day:1))!,revenue:rows.reduce(0){$0+$1.revenue},count:rows.reduce(0){$0+$1.orders})}}
    public static func parseRevenueMonths(_ data:JSONValue,shopID:UUID)->[RevenueMonth] {
        data["aggregations"]["channels"]["buckets"].array.flatMap { channel in channel["currencies"]["buckets"].array.flatMap { currency in currency["months"]["buckets"].array.compactMap { month in guard let channelID=channel["key"].string,let code=currency["key"].string,let key=month["key"].string,key.range(of:"^[0-9]{4}-[0-9]{2}$",options:.regularExpression) != nil else{return nil};return RevenueMonth(shopID:shopID,salesChannelID:channelID,currency:code,month:key,revenue:month["revenue"]["sum"].number ?? Double(month["revenue"]["sum"].string ?? "") ?? 0,orders:Int(month["count"].number ?? 0)) } } }
    }
}
extension ShopwareClient {
    public func salesChannels(_ shop:Shop)async throws->[CommerceSalesChannel] {
        if shop.isDemo {return DemoData.salesChannels(shop)}
        var rows:[CommerceSalesChannel]=[]
        for page in 1...100 {let result=try await adminRequest(shop,request:.init(method:"POST",path:"search/sales-channel",body:.object(["limit":.number(100),"page":.number(Double(page)),"total-count-mode":.number(1),"associations":.object(["domains":.object(["associations":.object(["currency":.object([:]),"language":.object(["associations":.object(["locale":.object([:])])])])]),"currencies":.object([:]),"type":.object([:])])])));rows += result["data"].array.map{CommerceSalesChannel(shopID:shop.id,data:$0)};if result["data"].array.isEmpty || rows.count>=Int(result["total"].number ?? Double(rows.count)){return rows}}
        throw ShopdeckError.message("Too many sales channels to load completely.")
    }
    public func revenueMonths(_ shop:Shop,now:Date=Date())async throws->[RevenueMonth] {
        if shop.isDemo {let rows=try await search(shop,entity:"order",page:1,limit:100).rows.map{AnalyticsOrder(shop:shop,data:$0)};let groups=Dictionary(grouping:rows.filter{!$0.cancelled}){($0.data["salesChannelId"].string ?? "")+"|"+$0.currency};return groups.map{key,rows in let parts=key.split(separator:"|");let d=Calendar.current.dateComponents([.year,.month],from:now);return RevenueMonth(shopID:shop.id,salesChannelID:String(parts[0]),currency:String(parts[1]),month:String(format:"%04d-%02d",d.year!,d.month!),revenue:rows.reduce(0){$0+($1.data["amountTotal"].number ?? 0)},orders:rows.count)}}
        let since=Calendar.current.date(from:Calendar.current.dateComponents([.year],from:now))!
        let stats:JSONValue = .object(["name":.string("channels"),"type":.string("terms"),"field":.string("salesChannelId"),"limit":.number(10000),"aggregation":.object(["name":.string("currencies"),"type":.string("terms"),"field":.string("currency.isoCode"),"limit":.number(1000),"aggregation":.object(["name":.string("months"),"type":.string("histogram"),"field":.string("orderDateTime"),"interval":.string("month"),"format":.string("Y-m"),"aggregation":.object(["name":.string("revenue"),"type":.string("stats"),"field":.string("amountTotal")])])])])
        let result=try await adminRequest(shop,request:.init(method:"POST",path:"search/order",body:.object(["limit":.number(1),"total-count-mode":.number(0),"filter":.array([.object(["type":.string("range"),"field":.string("orderDateTime"),"parameters":.object(["gte":.string(ISO8601DateFormatter().string(from:since)),"lte":.string(ISO8601DateFormatter().string(from:now))])]),.object(["type":.string("not"),"operator":.string("AND"),"queries":.array([.object(["type":.string("equals"),"field":.string("stateMachineState.technicalName"),"value":.string("cancelled")])])])]),"aggregations":.array([stats])])) )
        return CommerceAnalytics.parseRevenueMonths(result,shopID:shop.id)
    }
}

extension ShopwareClient {
    public func configureLocalDomains(_ shop:Shop,credentials:Credentials)async throws {
        guard ShopLinks.isManagedLocal(shop)else{throw ShopdeckError.message("Domain setup is restricted to Shopdeck local testshops.")}
        // Authenticate once using the supplied integration before it is persisted by the caller.
        try await testConnection(shop,credentials:credentials)
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("shopdeck-domain-"+UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:directory)}
        let transient=ShopwareClient(store:try WorkspaceStore(directory:directory),credentials:LocalSetupCredentials(value:credentials))
        let channels=try await transient.salesChannels(shop)
        for channel in channels where !channel.domains.isEmpty {
            for domain in channel.domains {guard let old=URL(string:domain.url),["localhost","127.0.0.1"].contains(old.host ?? "")else{continue};let new=shop.url+old.path;_ = try await transient.adminRequest(shop,request:.init(method:"PATCH",path:"sales-channel-domain/"+domain.id,body:.object(["url":.string(new)])))}
        }
    }
}
private struct LocalSetupCredentials:CredentialStorage {
    let value:Credentials
    func load(for shopID:UUID)throws->Credentials{value}
    func save(_ credentials:Credentials,for shopID:UUID)throws{}
    func delete(for shopID:UUID)throws{}
}
