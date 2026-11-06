import Foundation

public struct AdminAPIRequest:Codable,Sendable,Equatable {
    public var method:String
    public var path:String
    public var body:JSONValue
    public var query:[String:String]
    public init(method:String,path:String,body:JSONValue = .object([:]),query:[String:String]=[:]) {self.method=method.uppercased();self.path=path;self.body=body;self.query=query}
    public var isReadOnly:Bool { ["GET","HEAD"].contains(method) || method=="POST" && (path.hasPrefix("search/") || path.hasPrefix("aggregate/")) }
    public func validated() throws -> Self {
        var clean=self;clean.method=method.uppercased();clean.path=path.trimmingCharacters(in:CharacterSet(charactersIn:"/"))
        if clean.path.hasPrefix("api/"){clean.path=String(clean.path.dropFirst(4))}
        var decoded=clean.path
        for _ in 0..<4 {let next=decoded.removingPercentEncoding ?? decoded;if next==decoded{break};decoded=next}
        guard ["GET","HEAD","POST","PATCH","PUT","DELETE"].contains(clean.method),!decoded.isEmpty,!decoded.contains(":"),!decoded.contains("\\"),!decoded.contains("?"),!decoded.contains("#"),!decoded.contains("%"),!decoded.hasPrefix("/"),!decoded.split(separator:"/",omittingEmptySubsequences:false).contains(where:{$0==".." || $0=="." || $0.isEmpty}),!decoded.lowercased().hasPrefix("oauth"),!decoded.lowercased().hasPrefix("_mcp"),decoded.rangeOfCharacter(from:.controlCharacters)==nil else {throw ShopdeckError.message("Verwende einen relativen Admin API Pfad ohne Token oder vollständige URL.")}
        clean.path=decoded;return clean
    }
}
public struct AdminAPIProposal:Codable,Identifiable,Sendable {
    public var id=UUID()
    public var shopID:UUID
    public var shopName:String
    public var request:AdminAPIRequest
    public var reason:String
    public var status="pending"
    public var createdAt=Date()
    public var completedAt:Date?
    public var response:JSONValue?
    public var error:String?
    public init(shop:Shop,request:AdminAPIRequest,reason:String){shopID=shop.id;shopName=shop.name;self.request=request;self.reason=String(reason.prefix(2000))}
}
public struct AdminAPIQueue:Codable,Sendable {public var proposals:[AdminAPIProposal]=[];public init(){}}
public enum MCPDataProtection {
    public static func native(_ value:JSONValue,personalData:Bool)->JSONValue {
        var result=value.object ?? [:]
        result["content"] = .array(value["content"].array.map{item in
            guard item["type"].string=="text",let text=item["text"].string else{return .object(["type":.string("text"),"text":.string("Non-text native output omitted.")])}
            if let json=try? JSONDecoder().decode(JSONValue.self,from:Data(text.utf8)){return .object(["type":.string("text"),"text":.string(scrub(json,personalData:personalData).pretty)])}
            return .object(["type":.string("text"),"text":.string("Unstructured native output withheld. Check Shopdeck for the operation status.")])
        })
        return scrub(.object(result),personalData:personalData)
    }
    public static func scrub(_ value:JSONValue,personalData:Bool)->JSONValue {
        let secret=["password","passwordhash","secretaccesskey","clientsecret","accesstoken","refreshtoken","authorization","privatekey","token","accesskey","secret"]
        let personal=["firstname","lastname","email","street","zipcode","city","phonenumber","birthday","remoteaddress","ipaddress","ordercustomer","customer","addresses","billingaddress","shippingorderaddress","defaultbillingaddress","defaultshippingaddress","customfields","payload"]
        switch value {
        case .object(let object):
            if let key=object["configurationKey"]?.string,key.range(of:"password|secret|token|apikey|privatekey|accesskey|authorization",options:[.regularExpression,.caseInsensitive]) != nil{var clean=object;clean["configurationValue"] = .string("[redacted]");return .object(clean.mapValues{scrub($0,personalData:personalData)})}
            return .object(object.reduce(into:[:]) { result,entry in let key=entry.key.lowercased().replacingOccurrences(of:"_",with:"").replacingOccurrences(of:"-",with:"");if secret.contains(key) || key.range(of:"password|passwd|secret|token|apikey|privatekey|accesskey|authorization",options:.regularExpression) != nil || (!personalData && personal.contains(key)){result[entry.key] = .string("[redacted]")} else {result[entry.key]=scrub(entry.value,personalData:personalData)} })
        case .array(let rows):return .array(rows.map{scrub($0,personalData:personalData)})
        default:return value
        }
    }
}
extension WorkspaceStore {
    public func readAdminAPIQueue() throws -> AdminAPIQueue {try locked{try readLocalFile("admin-api-requests.json",fallback:AdminAPIQueue())}}
    @discardableResult public func updateAdminAPIQueue<T>(_ change:(inout AdminAPIQueue)throws->T)throws->T{try locked{var state=try readLocalFile("admin-api-requests.json",fallback:AdminAPIQueue());let result=try change(&state);try writeLocalFile(state,name:"admin-api-requests.json");return result}}
}
