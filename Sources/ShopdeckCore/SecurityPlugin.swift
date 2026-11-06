import Foundation
public struct SecurityPluginStatus:Sendable {
    public enum State:String,Sendable {case current,missing,inactive,outdated,unknown}
    public var state:State
    public var installed:String?
    public var latest:String?
    public var detail:String?
    public var checkedAt=Date()
    public init(state:State,installed:String?=nil,latest:String?=nil,detail:String?=nil){self.state=state;self.installed=installed;self.latest=latest;self.detail=detail}
    public static func assess(plugin:JSONValue?,latest:String?)->Self {
        guard let plugin else{return .init(state:.missing,latest:latest)}
        let version=plugin["version"].string
        guard plugin["active"].bool==true,plugin["installedAt"] != .null else{return .init(state:.inactive,installed:version,latest:latest)}
        guard let version,let latest else{return .init(state:.unknown,installed:version,detail:"Latest compatible version could not be verified.")}
        return .init(state:VersionComparison.isNewer(latest,than:version) ? .outdated:.current,installed:version,latest:latest)
    }
}
public actor SecurityPluginCatalog {
    public static let shared=SecurityPluginCatalog()
    private var versions:[String:JSONValue] = [:]
    private var loaded:Date?
    public func latestCompatible(with core:String)async throws->String? {
        if loaded==nil || Date().timeIntervalSince(loaded!)>86400 {
            var request=URLRequest(url:URL(string:"https://packages.shopware.com/packages.json")!);request.timeoutInterval=35
            let (data,response)=try await URLSession.shared.data(for:request)
            guard let response=response as? HTTPURLResponse,response.statusCode==200 else{throw ShopdeckError.message("Shopware security catalog is unavailable.")}
            let root=try JSONDecoder().decode(JSONValue.self,from:data);versions=root["packages"]["store.shopware.com/swagplatformsecurity"].object ?? [:];guard !versions.isEmpty else{throw ShopdeckError.message("Shopware security catalog did not contain the plugin.")};loaded=Date()
        }
        return versions.values.filter{Self.supports(core,requirement:$0["require"]["shopware/core"].string ?? "*")}.compactMap{$0["version"].string}.filter{$0.range(of:"^[0-9]+(\\.[0-9]+){1,3}$",options:.regularExpression) != nil}.max{VersionComparison.isNewer($1,than:$0)}
    }
    public static func supports(_ core:String,requirement:String)->Bool {
        func parts(_ s:String)->[Int]{s.split(separator:".").compactMap{Int($0)}}
        if requirement=="*"{return true}
        if requirement.hasPrefix("~"){let p=parts(String(requirement.dropFirst())),v=parts(core);return p.count>=2 && v.count>=2 && p[0]==v[0] && p[1]==v[1] && !VersionComparison.isNewer(String(requirement.dropFirst()),than:core)}
        let tokens=requirement.split(separator:" ")
        return !tokens.isEmpty && tokens.allSatisfy{token in let t=String(token);if t.hasPrefix(">="){return !VersionComparison.isNewer(String(t.dropFirst(2)),than:core)};if t.hasPrefix("<"){return VersionComparison.isNewer(String(t.dropFirst()),than:core)};return false}
    }
}
extension ShopwareClient {
    public func securityPlugin(_ shop:Shop)async throws->SecurityPluginStatus {
        if shop.isDemo {let index=DemoData.shops.firstIndex(where:{$0.id==shop.id}) ?? 0;return .init(state:index==0 ? .current:index==1 ? .missing:.outdated,installed:index==1 ? nil:index==0 ? "4.0.16":"4.0.12",latest:"4.0.16",detail:"Demonstration")}
        let core=try await version(shop)
        let data=try await adminRequest(shop,request:.init(method:"POST",path:"search/plugin",body:.object(["limit":.number(1),"filter":.array([.object(["type":.string("equals"),"field":.string("name"),"value":.string("SwagPlatformSecurity")])])])) )
        let latest=try? await SecurityPluginCatalog.shared.latestCompatible(with:core)
        return .assess(plugin:data["data"].array.first,latest:latest)
    }
}
