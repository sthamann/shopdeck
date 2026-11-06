import XCTest
@testable import ShopdeckCore
final class CommerceAnalyticsTests:XCTestCase {
    func testRevenueSeparatesCurrenciesAndCancellationsAndCalendarDays() throws {
        let now=ISO8601DateFormatter().date(from:"2026-11-06T12:00:00Z")!
        let shop=Shop(name:"One",url:"https://one.example")
        func order(_ amount:Double,_ currency:String,_ state:String,_ days:Int)->AnalyticsOrder {let date=Calendar.current.date(byAdding:.day,value:-days,to:now)!;return .init(shop:shop,data:.object(["id":.string(UUID().uuidString),"amountTotal":.number(amount),"currency":.object(["isoCode":.string(currency)]),"stateMachineState":.object(["technicalName":.string(state)]),"orderDateTime":.string(ISO8601DateFormatter().string(from:date))]))}
        var analytics=CommerceAnalytics();analytics.orders=[order(100,"EUR","open",0),order(90,"EUR","cancelled",0),order(25,"USD","open",0),order(50,"EUR","open",6),order(500,"EUR","open",7)]
        XCTAssertEqual(analytics.revenue(days:1,currency:"EUR",now:now),100)
        XCTAssertEqual(analytics.revenue(days:7,currency:"EUR",now:now),150)
        XCTAssertEqual(analytics.revenue(days:1,currency:"USD",now:now),25)
        XCTAssertEqual(analytics.period(days:1,currency:"EUR",now:now).count,2)
        let series=analytics.series(days:7,currency:"EUR",now:now)
        XCTAssertEqual(series.count,7);XCTAssertEqual(series.reduce(0){$0+$1.revenue},150)
        XCTAssertEqual(DashboardWidget.allCases.count,23)
        XCTAssertEqual(Set(DashboardConfiguration().widgets).count,23)
    }
    func testDashboardOrderPersistsAndOldWorkbenchStillLoads() throws {
        let store=try WorkspaceStore(directory:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        var config=DashboardConfiguration();config.widgets=[.revenue7,.ordersToday,.customers]
        try store.updateWorkbench{$0.dashboard=config}
        XCTAssertEqual(try WorkspaceStore(directory:store.directory).readWorkbench().dashboard,config)
        let old=try JSONDecoder().decode(Workbench.self,from:Data("{\"savedViews\":[]}".utf8));XCTAssertNil(old.dashboard)
    }
}
