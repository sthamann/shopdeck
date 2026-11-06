import Foundation
import Security

public struct CommerceWidgetDay: Codable, Sendable { public let date: Date; public let revenue: Double; public let count: Int; public init(date: Date,revenue: Double,count: Int) { self.date=date;self.revenue=revenue;self.count=count } }
public struct CommerceWidgetItem:Codable,Sendable {public var title:String;public var value:String;public init(title:String,value:String){self.title=title;self.value=value}}
public struct CommerceWidgetScope: Codable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var isDemo: Bool
    public var updatedAt: Date
    public var metrics: [String: [String: String]]
    public var highlights:[String:[CommerceWidgetItem]]?
    public var series: [String: [CommerceWidgetDay]]
    public init(id:String,name:String,isDemo:Bool,updatedAt:Date,metrics:[String:[String:String]],series:[String:[CommerceWidgetDay]],highlights:[String:[CommerceWidgetItem]]?=nil) {self.highlights=highlights; self.id=id;self.name=name;self.isDemo=isDemo;self.updatedAt=updatedAt;self.metrics=metrics;self.series=series }
}
public struct CommerceWidgetSnapshot: Codable, Sendable {
    public static let group = "YXRJR897BM.app.shopdeck"
    public static let filename = "commerce-widgets.json"
    public var scopes: [CommerceWidgetScope] = []
    public init() {}
    public static var canShare:Bool {
        var code:SecCode?;guard SecCodeCopySelf([], &code)==errSecSuccess,let code else{return false}
        var staticCode:SecStaticCode?;guard SecCodeCopyStaticCode(code,[],&staticCode)==errSecSuccess,let staticCode else{return false}
        var info:CFDictionary?;guard SecCodeCopySigningInformation(staticCode,SecCSFlags(rawValue:kSecCSSigningInformation),&info)==errSecSuccess,let values=info as? [String:Any],let team=values[kSecCodeInfoTeamIdentifier as String] as? String else{return false};return !team.isEmpty
    }
    public static var url: URL? { guard canShare else{return nil};return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent(filename) }
    public static func read() -> Self { guard let url,let data=try? Data(contentsOf:url),let result=try? JSONDecoder().decode(Self.self,from:data) else {return .init()};return result }
}
