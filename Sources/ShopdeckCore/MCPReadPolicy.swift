import Foundation

public enum MCPReadPolicy {
    public static func entity(_ request:AdminAPIRequest)->String? {let parts=request.path.split(separator:"/");guard let first=parts.first else{return nil};return String(["search","aggregate"].contains(first) && parts.count>1 ? parts[1]:first).replacingOccurrences(of:"_",with:"-")}
    public static func validate(_ request:AdminAPIRequest,personalData:Bool)throws {
        guard request.isReadOnly else{throw ShopdeckError.message("Queue writes for approval in Shopdeck.")}
        guard !personalData else{return}
        if request.path.hasPrefix("_info/") || request.path=="_action/mcp/capabilities"{return}
        let safe:Set<String>=["product","product-manufacturer","product-media","product-visibility","category","cms-page","cms-section","cms-block","cms-slot","landing-page","media","media-folder","media-thumbnail","sales-channel","sales-channel-domain","currency","language","locale","tax","unit","delivery-time","property-group","property-group-option","tag","theme","country","country-state","shipping-method","payment-method","plugin"]
        guard let entity=entity(request),safe.contains(entity) else{throw ShopdeckError.message("This endpoint is not classified as non-personal. Customer records require customer data sharing; use search_orders/get_order for redacted orders.")}
        func sensitive(_ field:String)->Bool{let parts=field.lowercased().replacingOccurrences(of:"-",with:"").replacingOccurrences(of:"_",with:"").split(separator:".");return parts.contains{part in ["customer","order","user","newsletter","integration"].contains{part.hasPrefix($0)}}}
        let path=request.path.split(separator:"/").map(String.init)
        let associationStart=["search","aggregate"].contains(path.first ?? "") ? 3:2
        if path.count>associationStart,path.dropFirst(associationStart).contains(where:sensitive){throw ShopdeckError.message("This association requires customer data sharing.")}
        for (key,value) in request.query{if sensitive(key){throw ShopdeckError.message("This query includes a personal association.")};if let json=try? JSONDecoder().decode(JSONValue.self,from:Data(value.utf8)){try check(json)}}
        func check(_ value:JSONValue)throws {
            switch value {
            case .object(let object):for (key,child) in object{if ["associations","includes"].contains(key),let fields=child.object{for field in fields.keys{let normalized=field.lowercased().replacingOccurrences(of:"-",with:"").replacingOccurrences(of:"_",with:"");if sensitive(normalized){throw ShopdeckError.message("The requested association contains personal or access data. Enable the relevant sharing permission or remove it.")}}};try check(child)}
            case .array(let values):for child in values{try check(child)}
            default:break
            }
        }
        try check(request.body)
    }
}
public enum MCPProjection {
    public static func fields(_ input:JSONValue,entity:String,detail:Bool=false)throws->[String] {
        let defaults=entity=="product" ? ["id","productNumber","name","stock","active","cover.media.url"]:entity=="order" ? ["id","orderNumber","orderDateTime","amountTotal","currency.isoCode","stateMachineState.technicalName","salesChannelId"]:["id","customerNumber","firstName","lastName","email","active"]
        let fields=input == .null ? defaults+(detail && entity=="product" ? ["description","price"]:[]):input.array.compactMap(\.string)
        guard !fields.isEmpty,fields.count<=24,fields.allSatisfy({$0.count<=150 && $0.range(of:"^[A-Za-z][A-Za-z0-9_.]*$",options:.regularExpression) != nil})else{throw ShopdeckError.message("Choose 1–24 field paths, for example id, name or cover.media.url.")}
        return Array(Set(["id"]+fields)).sorted()
    }
    public static func project(_ row:JSONValue,fields:[String])->JSONValue {
        var result:[String:JSONValue]=[:]
        // Dotted field keys deliberately avoid returning large nested association objects.
        for field in fields{result[field]=row.at(field)}
        return .object(result)
    }
}
