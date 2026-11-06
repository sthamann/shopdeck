import Foundation

public struct RecordSort:Codable,Equatable,Sendable {
    public var field:String
    public var ascending:Bool
    public init(_ field:String,ascending:Bool=true){self.field=field;self.ascending=ascending}
    public static func defaults(_ entity:String)->[Self]{[.init(entity=="product" ? "name":entity=="order" ? "orderDateTime":"lastName",ascending:entity != "order"),.init("id")]}
    public func criteria()throws->JSONValue {
        guard field.range(of:"^[A-Za-z][A-Za-z0-9_.]*$",options:.regularExpression) != nil,field.count<=150,!field.split(separator:".").contains(where:{Int($0) != nil})else{throw ShopdeckError.message("This field cannot be sorted by the Shopware Admin API.")}
        return .object(["field":.string(field),"order":.string(ascending ? "ASC":"DESC"),"naturalSorting":.bool(false)])
    }
}
public struct FederatedRecord:Sendable {public let shop:Shop;public let data:JSONValue;public init(shop:Shop,data:JSONValue){self.shop=shop;self.data=data};public var id:String{shop.id.uuidString+data["id"].displayString}}
public struct FederatedSearchPage:Sendable {public var rows:[FederatedRecord];public var total:Int;public var hasNext:Bool;public var capped:Bool;public var failures:[String];public var fetched:Int}
extension ShopwareClient {
    /// Each shop sorts its entire matching data set before pagination. A prefix of N
    /// rows from every shop contains the global top N. No page is sorted in isolation.
    public func searchAcrossShops(_ shops:[Shop],entity:String,term:String="",page:Int=1,pageSize:Int=50,maximum:Int=1000,sort:[RecordSort]=[],lowStock:Bool=false,status:String="all",filters:[UUID:[RecordFilter]]=[:])async throws->FederatedSearchPage {
        let now = Date()
        let filters = try filters.mapValues { values in try values.flatMap { try $0.freezingDateRange(now: now) } }
        let cap=min(max(maximum,1),10000),size=min(max(pageSize,1),cap),number=max(page,1),prefix=min(number*size,cap)
        var sorting=sort.isEmpty ? RecordSort.defaults(entity):sort
        if !sorting.contains(where:{$0.field=="id"}){sorting.append(.init("id"))}
        let remote=sorting.filter{$0.field != "shop"}
        _ = try remote.map{try $0.criteria()}
        // A fixed batch size for all pages avoids changing the API's page offsets.
        func gcd(_ a:Int,_ b:Int)->Int{b==0 ? a:gcd(b,a%b)}
        let batch=gcd(prefix,100)
        var all:[FederatedRecord]=[],total=0,failures:[String]=[],fetched=0
        try await withThrowingTaskGroup(of:(Shop,[JSONValue],Int,String?).self){group in
            for shop in shops {group.addTask{[self] in
                do {
                    var rows:[JSONValue]=[],count=0
                    for apiPage in 1...max(1,prefix/batch){try Task.checkCancellation();let result=try await self.search(shop,entity:entity,term:term,page:apiPage,limit:batch,lowStock:lowStock,status:status,customFilters:filters[shop.id] ?? [],sort:remote);count=result.total;rows += result.rows;if rows.count>=count || result.rows.isEmpty{break}}
                    return (shop,rows,count,nil)
                }catch is CancellationError{throw CancellationError()}catch{return(shop,[],0,error.localizedDescription)}
            }}
            for try await (shop,rows,count,error) in group {all += rows.map{.init(shop:shop,data:$0)};total += count;fetched += rows.count;if let error{failures.append(shop.name+": "+error)}}
        }
        try Task.checkCancellation()
        let indices=RecordOrdering.indices(rows:all.map(\.data),shops:all.map{$0.shop.name},ids:all.map(\.id),descriptors:sorting.map{($0.field,$0.ascending)})
        let ordered=indices.prefix(prefix).map{all[$0]},offset=(number-1)*size
        return .init(rows:Array(ordered.dropFirst(offset).prefix(size)),total:total,hasNext:number*size<min(total,cap),capped:total>cap,failures:failures,fetched:fetched)
    }
}
