import Foundation
extension ShopwareClient {
    /// A successful action response and an independently confirmed entity write are different receipts.
    public func executeAdminApproval(_ shop:Shop,request:AdminAPIRequest)async throws->JSONValue {
        let action=try request.validated(),response=try await adminRequest(shop,request:action)
        let parts=action.path.split(separator:"/").map(String.init)
        var result:[String:JSONValue]=["response":response,"http_success":.bool(true),"verification":.string("action_response_only")]
        guard !action.isReadOnly,let entity=parts.first,entity.range(of:"^[a-z][a-z0-9-]*$",options:.regularExpression) != nil,parts.count<=2,let id=parts.count==2 ? parts[1]:action.body["id"].string,(try? Validation.entityID(id)) != nil else{return .object(result)}
        var body:[String:JSONValue]=["ids":.array([.string(id)]),"limit":.number(1)]
        if entity=="cms-page"{body["associations"] = .object(["sections":.object(["associations":.object(["blocks":.object(["associations":.object(["slots":.object([:])])])])])])}
        let readback=try await adminRequest(shop,request:.init(method:"POST",path:"search/"+entity,body:.object(body)))
        if action.method=="DELETE"{guard readback["data"].array.isEmpty else{throw ShopdeckError.message("The delete response succeeded, but the record still exists. Check the operation before retrying.")}}
        else{guard let saved=readback["data"].array.first,Self.matchesExpected(action.body,in:saved) else{throw ShopdeckError.message("The write response succeeded, but the saved values did not match. Check the operation before retrying.")}}
        result["verification"] = .string("independent_read_back");result["entity"] = .string(entity);result["id"] = .string(id)
        return .object(result)
    }
    public static func matchesExpected(_ expected:JSONValue,in actual:JSONValue)->Bool {
        switch expected{
        case .object(let fields):return fields.allSatisfy{key,value in matchesExpected(value,in:actual[key])}
        case .array(let values):guard case .array(let rows)=actual, !values.isEmpty || rows.isEmpty else{return false};return values.allSatisfy{item in if let id=item["id"].string{return actual.array.contains{$0["id"].string==id && matchesExpected(item,in:$0)}};return actual.array.contains{matchesExpected(item,in:$0)}}
        default:return expected==actual
        }
    }
}
