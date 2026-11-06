import XCTest
@testable import ShopdeckCore
final class CommerceScopeTests:XCTestCase {
    func testSortingKeepsAllFieldsAndShopIdentityTogether() {
        let rows:[JSONValue] = [.object(["id":.string("A"),"name":.string("Lamp 10"),"stock":.number(2)]),.object(["id":.string("B"),"name":.string("Lamp 2"),"stock":.number(19)]),.object(["id":.string("C"),"name":.string("Lamp 1"),"stock":.null])]
        let shops=["West","East","West"],ids=["A","B","C"]
        for descriptors:[(String,Bool)] in [[("stock",true)],[("stock",false)],[("name",true)],[("shop",true),("stock",true)]] {
            let sorted=RecordOrdering.indices(rows:rows,shops:shops,ids:ids,descriptors:descriptors)
            XCTAssertEqual(Set(sorted),Set([0,1,2]))
            for i in sorted {XCTAssertEqual(rows[i]["id"].string,ids[i]);XCTAssertEqual(rows[i]["name"].string, i==0 ? "Lamp 10":i==1 ? "Lamp 2":"Lamp 1")}
        }
        XCTAssertEqual(RecordOrdering.indices(rows:rows,shops:shops,ids:ids,descriptors:[("name",true)]),[2,0,1])
        XCTAssertEqual(RecordOrdering.indices(rows:rows,shops:shops,ids:ids,descriptors:[("stock",false)]),[1,0,2])
    }
    func testYearMonthChannelAndCurrencyAreIndependent() throws {
        let a=UUID(),b=UUID(),now=ISO8601DateFormatter().date(from:"2026-11-06T12:00:00Z")!
        var value=CommerceAnalytics()
        value.revenueMonths=[.init(shopID:a,salesChannelID:"online",currency:"EUR",month:"2026-11",revenue:100,orders:2),.init(shopID:b,salesChannelID:"online",currency:"EUR",month:"2026-11",revenue:200,orders:3),.init(shopID:a,salesChannelID:"outlet",currency:"EUR",month:"2026-01",revenue:50,orders:1),.init(shopID:a,salesChannelID:"online",currency:"USD",month:"2026-11",revenue:900,orders:1),.init(shopID:a,salesChannelID:"online",currency:"EUR",month:"2025-11",revenue:800,orders:1)]
        XCTAssertEqual(value.calendarRevenue(.month,currency:"EUR",now:now),300)
        XCTAssertEqual(value.calendarRevenue(.year,currency:"EUR",now:now),350)
        let channel=value.scoped(shopIDs:[a,b],channelKeys:[a.uuidString+":online"])
        XCTAssertEqual(channel.calendarRevenue(.year,currency:"EUR",now:now),100)
        XCTAssertEqual(channel.calendarRevenue(.month,currency:"USD",now:now),900)
        XCTAssertEqual(value.monthlySeries(currency:"EUR",now:now).reduce(0){$0+$1.revenue},350)
    }
    func testRealShopwareAggregationShapeAndStringSum() throws {
        let data=try JSONDecoder().decode(JSONValue.self,from:Data(#"{"aggregations":{"channels":{"buckets":[{"key":"channel","currencies":{"buckets":[{"key":"EUR","months":{"buckets":[{"key":"2026-11","count":2,"revenue":{"sum":"119.50"}}]}}]}}]}}}"#.utf8))
        let rows=CommerceAnalytics.parseRevenueMonths(data,shopID:UUID())
        XCTAssertEqual(rows.count,1);XCTAssertEqual(rows.first?.revenue,119.5);XCTAssertEqual(rows.first?.orders,2)
    }
    func testDashboardLegacyMigrationAndDuplicateTileReorderPersistScopes() throws {
        let old=try JSONDecoder().decode(DashboardConfiguration.self,from:Data(#"{"widgets":["ordersToday","revenue7"]}"#.utf8))
        var config=old;var copy=old.effectiveTiles[0];copy.id="copy";copy.shopIDs=[UUID(),UUID()];copy.currency="USD";copy.showShops=true
        config.tiles=old.effectiveTiles+[copy];config.moveTile("copy",before:"ordersToday")
        let restored=try JSONDecoder().decode(DashboardConfiguration.self,from:JSONEncoder().encode(config))
        XCTAssertEqual(restored.effectiveTiles.map(\.id),["copy","ordersToday","revenue7"])
        XCTAssertEqual(restored.effectiveTiles[0].shopIDs?.count,2);XCTAssertEqual(restored.effectiveTiles[0].currency,"USD")
    }
    func testSecurityStatusAndCompatibleVersionConstraints() {
        XCTAssertTrue(SecurityPluginCatalog.supports("6.7.16.0",requirement:"~6.7.0"))
        XCTAssertFalse(SecurityPluginCatalog.supports("6.6.10.0",requirement:"~6.7.0"))
        XCTAssertFalse(SecurityPluginCatalog.supports("6.5.0.0",requirement:">=6.1.0 <6.5.0"))
        XCTAssertEqual(SecurityPluginStatus.assess(plugin:nil,latest:"4.0.16").state,.missing)
        let plugin:JSONValue = .object(["version":.string("4.0.12"),"active":.bool(true),"installedAt":.string("2026-01-01")])
        XCTAssertEqual(SecurityPluginStatus.assess(plugin:plugin,latest:"4.0.16").state,.outdated)
        XCTAssertEqual(SecurityPluginStatus.assess(plugin:plugin,latest:nil).state,.unknown)
        XCTAssertEqual(SecurityPluginStatus.assess(plugin:.object(["version":.string("4.0.16"),"active":.bool(false)]),latest:"4.0.16").state,.inactive)
    }
    func testLocalCredentialsBannerOnlyForManagedLoopbackShop() {
        var shop=Shop(name:"Local",url:"http://127.0.0.1:18888");shop.containerName="shopdeck-test"
        XCTAssertTrue(ShopLinks.isManagedLocal(shop));shop.url="https://remote.example";XCTAssertFalse(ShopLinks.isManagedLocal(shop))
    }
}
