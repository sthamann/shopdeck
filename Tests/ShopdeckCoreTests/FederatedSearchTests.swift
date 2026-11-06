import XCTest
@testable import ShopdeckCore
final class FederatedSearchTests:XCTestCase {
    func testRemoteSortSearchFiltersAndGlobalPagesBeyondFiftyRows()async throws {
        let store=try WorkspaceStore(directory:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)),credentials=MemoryCredentials()
        let shops=[Shop(name:"A",url:"https://a.example"),Shop(name:"B",url:"https://b.example")]
        for shop in shops{try credentials.save(.init(clientID:"test",clientSecret:"test"),for:shop.id)}
        let lock=NSLock();var calls:[(String,JSONValue)]=[]
        MockProtocol.handler={request in
            if request.url!.path.hasSuffix("oauth/token"){return(200,.object(["access_token":.string("test"),"expires_in":.number(600)]))}
            let body=try Self.body(request);lock.lock();calls.append((request.url!.host!,body));lock.unlock()
            let offset=request.url!.host=="a.example" ? 0:1
            var rows:[JSONValue]=(0..<300).map{i in .object(["id":.string(String(format:"%032x",i+1)),"name":.string("needle \(i)"),"stock":.number(Double(i*2+offset)),"active":.bool(true)])}
            XCTAssertEqual(body["term"].string,"needle")
            XCTAssertEqual(body["sort"].array.first?["field"].string,"stock")
            XCTAssertEqual(body["sort"].array.first?["order"].string,"DESC")
            XCTAssertTrue(body["filter"].array.contains{$0["field"].string=="stock" && $0["parameters"]["gte"].number==450})
            rows=rows.filter{($0["stock"].number ?? 0)>=450}.sorted{$0["stock"].number!>$1["stock"].number!}
            let size=Int(body["limit"].number!),page=Int(body["page"].number!)
            return (200,.object(["data":.array(Array(rows.dropFirst((page-1)*size).prefix(size))),"total":.number(Double(rows.count))]))
        }
        defer{MockProtocol.handler=nil}
        let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[MockProtocol.self]
        let client=ShopwareClient(store:store,credentials:credentials,session:URLSession(configuration:configuration))
        let filters=Dictionary(uniqueKeysWithValues:shops.map{($0.id,[RecordFilter(name:"High",field:"stock",operation:"gte",value:"450")])})
        let first=try await client.searchAcrossShops(shops,entity:"product",term:"needle",page:1,pageSize:25,maximum:100,sort:[.init("stock",ascending:false)],filters:filters)
        let second=try await client.searchAcrossShops(shops,entity:"product",term:"needle",page:2,pageSize:25,maximum:100,sort:[.init("stock",ascending:false)],filters:filters)
        XCTAssertEqual(first.total,150);XCTAssertEqual(first.rows.compactMap{$0.data["stock"].number},(575...599).reversed().map(Double.init))
        XCTAssertEqual(second.rows.compactMap{$0.data["stock"].number},(550...574).reversed().map(Double.init))
        XCTAssertTrue(Set(first.rows.map(\.id)).isDisjoint(with:second.rows.map(\.id)))
        XCTAssertTrue(first.hasNext);XCTAssertTrue(first.capped);XCTAssertEqual(first.fetched,50)
        XCTAssertEqual(Set(calls.map(\.0)),["a.example","b.example"])
    }
    func testConfiguredCapAndSelectedShopAreRespected()async throws {
        let store=try WorkspaceStore(directory:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString));try store.addDemoShops()
        let client=ShopwareClient(store:store)
        let page=try await client.searchAcrossShops([DemoData.shops[1]],entity:"product",page:2,pageSize:5,maximum:10,sort:[.init("stock",ascending:false)])
        XCTAssertEqual(page.total,24);XCTAssertEqual(page.rows.count,5);XCTAssertEqual(page.fetched,10);XCTAssertFalse(page.hasNext);XCTAssertTrue(page.capped)
        XCTAssertTrue(page.rows.allSatisfy{$0.shop.id==DemoData.shops[1].id})
        XCTAssertThrowsError(try RecordSort("price.0.gross").criteria())
    }
    private static func body(_ request:URLRequest)throws->JSONValue {
        if let data=request.httpBody{return try JSONDecoder().decode(JSONValue.self,from:data)}
        guard let stream=request.httpBodyStream else{return .null};stream.open();defer{stream.close()};var data=Data(),buffer=[UInt8](repeating:0,count:4096)
        while stream.hasBytesAvailable{let n=stream.read(&buffer,maxLength:buffer.count);if n<=0{break};data.append(contentsOf:buffer.prefix(n))}
        return try JSONDecoder().decode(JSONValue.self,from:data)
    }
}
