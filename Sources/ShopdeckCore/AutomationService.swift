import Foundation

public enum CampaignBuilder {
    static func id()->String{UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased()}
    public static func make(_ input:JSONValue,assets:[StagedAsset])throws->JSONValue {
        let title=input["title"].string ?? "",sections=input["sections"].array
        guard !title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,title.count<=200,!sections.isEmpty,sections.count<=20 else{throw ShopdeckError.message("A campaign needs a title and 1–20 sections.")}
        let channel=try Validation.entityID(input["sales_channel_id"].string ?? "")
        var blocks:[JSONValue]=[]
        for (position,section) in sections.enumerated(){
            let type=section["type"].string ?? "",blockType:String,slotType:String,config:JSONValue
            switch type {
            case "text":
                guard let text=section["text"].string,text.count<=20_000 else{throw ShopdeckError.message("Text sections need at most 20,000 characters.")}
                let html=text.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\n",with:"<br>")
                blockType="text";slotType="text";config = .object(["content":.object(["source":.string("static"),"value":.string("<p>"+html+"</p>")])])
            case "image":
                guard let index=section["file_index"].number,index.rounded()==index,assets.indices.contains(Int(index)) else{throw ShopdeckError.message("Image sections need a file_index matching the prepared files.")}
                blockType="image";slotType="image";config = .object(["media":.object(["source":.string("static"),"value":.string("asset:"+assets[Int(index)].id)]),"displayMode":.object(["source":.string("static"),"value":.string("standard")]),"verticalAlign":.object(["source":.string("static"),"value":.string("center")])])
            case "product_slider":
                let products=try section["product_ids"].array.map{try Validation.entityID($0.string ?? "")};guard !products.isEmpty,products.count<=30 else{throw ShopdeckError.message("A product slider needs 1–30 product IDs.")}
                blockType="product-slider";slotType="product-slider";config = .object(["products":.object(["source":.string("static"),"value":.array(products.map(JSONValue.string))]),"title":.object(["source":.string("static"),"value":.string(section["title"].string ?? "")]),"boxLayout":.object(["source":.string("static"),"value":.string("standard")]),"displayMode":.object(["source":.string("static"),"value":.string("standard")]),"navigation":.object(["source":.string("static"),"value":.bool(true)]),"rotate":.object(["source":.string("static"),"value":.bool(false)]),"border":.object(["source":.string("static"),"value":.bool(false)]),"elMinWidth":.object(["source":.string("static"),"value":.string("250px")])])
            default:throw ShopdeckError.message("Section type must be text, image or product_slider.")
            }
            blocks.append(.object(["id":.string(id()),"type":.string(blockType),"position":.number(Double(position)),"sectionPosition":.string("main"),"marginTop":.string("20px"),"marginBottom":.string("20px"),"marginLeft":.string("20px"),"marginRight":.string("20px"),"slots":.array([.object(["id":.string(id()),"type":.string(slotType),"slot":.string("content"),"config":config])])]))
        }
        return .object(["page":.object(["id":.string(id()),"name":.string(title),"type":.string("landingpage"),"sections":.array([.object(["id":.string(id()),"type":.string("default"),"position":.number(0),"sizingMode":.string("boxed"),"blocks":.array(blocks)])])]),"landing_page_id":.string(id()),"sales_channel_id":.string(channel),"publish":.bool(input["publish"].bool ?? false),"sections":.array(sections)])
    }
}

/// Every remote step is preceded by a persisted checkpoint. Failed/unknown operations are never silently replayed.
public actor AutomationService {
    let store:WorkspaceStore
    let client:ShopwareClient
    public init(store:WorkspaceStore,client:ShopwareClient){self.store=store;self.client=client}
    public func execute(_ id:UUID,shop:Shop)async throws->AutomationOperation {
        let operation=try store.updateAutomationQueue{queue->AutomationOperation in guard let index=queue.operations.firstIndex(where:{$0.id==id && $0.shopID==shop.id && $0.status=="pending"})else{throw ShopdeckError.message("The operation is no longer pending.")};queue.operations[index].status="executing";return queue.operations[index]}
        do {
            let result:JSONValue
            switch operation.kind {
            case "media":guard let file=operation.files.first else{throw ShopdeckError.message("Prepared file is missing.")};result=try await upload(file,operation:id,shop:shop)
            case "plugin":result=try await installPlugin(operation,shop:shop)
            case "campaign":result=try await createCampaign(operation,shop:shop)
            case "native_mcp":try checkpoint(id,"native_call",.string("started"));result=try await client.callOfficialMCP(shop,name:operation.payload["name"].string ?? "",arguments:operation.payload["arguments"])
            default:throw ShopdeckError.message("Unknown operation kind.")
            }
            try store.updateAutomationQueue{queue in if let index=queue.operations.firstIndex(where:{$0.id==id}){queue.operations[index].status="applied";queue.operations[index].result=operation.kind=="native_mcp" ? MCPDataProtection.native(result,personalData:shop.shareCustomerData):MCPDataProtection.scrub(result,personalData:shop.shareCustomerData);queue.operations[index].completedAt=Date()}}
        }catch{
            let detail=error.localizedDescription
            try store.updateAutomationQueue{queue in if let index=queue.operations.firstIndex(where:{$0.id==id}){queue.operations[index].status=queue.operations[index].checkpoints.isEmpty ? "failed":"needs_review";queue.operations[index].error=detail;queue.operations[index].completedAt=Date()}}
            throw error
        }
        return try store.readAutomationQueue().operations.first{$0.id==id}!
    }
    private func checkpoint(_ id:UUID,_ step:String,_ result:JSONValue)throws{try store.updateAutomationQueue{queue in guard let index=queue.operations.firstIndex(where:{$0.id==id})else{throw ShopdeckError.message("Approval record disappeared.")};queue.operations[index].checkpoints[step]=result}}
    private func upload(_ asset:StagedAsset,operation:UUID,shop:Shop)async throws->JSONValue {
        let data=try store.stagedData(asset),mediaID=CampaignBuilder.id()
        try checkpoint(operation,"media:"+asset.id,.object(["id":.string(mediaID),"status":.string("creating")]))
        _ = try await client.adminRequest(shop,request:.init(method:"POST",path:"media",body:.object(["id":.string(mediaID)])))
        let safeName=asset.name.replacingOccurrences(of:"[^A-Za-z0-9_-]",with:"-",options:.regularExpression)
        _ = try await client.uploadBinary(shop,path:"_action/media/\(mediaID)/upload",data:data,contentType:asset.mimeType,query:["extension":asset.fileExtension,"fileName":(safeName.isEmpty ? "shopdeck-image":safeName)+"-"+String(mediaID.prefix(8))])
        let row=try await read(shop,entity:"media",id:mediaID)
        guard row["hasFile"].bool==true,Int(row["fileSize"].number ?? -1)==data.count,row["fileExtension"].string==asset.fileExtension else{throw ShopdeckError.message("Media upload returned, but its stored size or extension could not be verified.")}
        let result:JSONValue = .object(["id":.string(mediaID),"fileName":row["fileName"],"extension":row["fileExtension"],"url":row["url"],"preview_url":row["url"],"sha256":.string(asset.sha256),"verified":.bool(true)])
        try checkpoint(operation,"media:"+asset.id,result);return result
    }
    private func installPlugin(_ operation:AutomationOperation,shop:Shop)async throws->JSONValue {
        guard let asset=operation.files.first,let name=asset.metadata["technicalName"].string else{throw ShopdeckError.message("The plugin package is missing.")}
        let data=try store.stagedData(asset),boundary="Shopdeck"+UUID().uuidString
        let version=try await client.version(shop)
        guard ComposerConstraint.matches(version,requirement:asset.metadata["coreConstraint"].string ?? "") else{throw ShopdeckError.message("The package does not declare compatibility with Shopware "+version+". No file was uploaded.")}
        let previous=try await client.adminRequest(shop,request:.init(method:"POST",path:"search/plugin",body:.object(["limit":.number(1),"filter":.array([.object(["type":.string("equals"),"field":.string("name"),"value":.string(name)])])])))
        if let installed=previous["data"].array.first,installed["installedAt"] != .null{throw ShopdeckError.message("This plugin is already installed. A separate update operation is required. No package was uploaded.")}
        // Shopware performs the authoritative check for all remaining dependencies during installation.
        try checkpoint(operation.id,"compatibility",.object(["shopware":.string(version),"required":asset.metadata["coreConstraint"],"dependency_check":.string("Shopware installer is authoritative")]))
        var multipart=Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"plugin.zip\"\r\nContent-Type: application/zip\r\n\r\n".utf8);multipart.append(data);multipart.append(Data("\r\n--\(boundary)--\r\n".utf8))
        try checkpoint(operation.id,"package_upload",.string("started"))
        _ = try await client.uploadBinary(shop,path:"_action/extension/upload",data:multipart,contentType:"multipart/form-data; boundary=\(boundary)")
        _ = try await client.adminRequest(shop,request:.init(method:"POST",path:"_action/extension/refresh"))
        let found=try await plugin(shop,name:name)
        guard found["version"]==asset.metadata["version"] else{throw ShopdeckError.message("The uploaded plugin version does not match the approved package.")}
        try checkpoint(operation.id,"package_upload",.object(["id":found["id"],"version":found["version"]]))
        guard found["installedAt"] == .null else{throw ShopdeckError.message("This plugin is already installed. Updating an installed plugin requires a separate update operation.")}
        try checkpoint(operation.id,"installation",.string("started"))
        _ = try await client.adminRequest(shop,request:.init(method:"POST",path:"_action/extension/install/plugin/"+name))
        if operation.payload["activate"].bool==true{try checkpoint(operation.id,"activation",.string("started"));_ = try await client.adminRequest(shop,request:.init(method:"PUT",path:"_action/extension/activate/plugin/"+name))}
        let installed=try await plugin(shop,name:name)
        guard installed["installedAt"] != .null,installed["version"]==asset.metadata["version"],operation.payload["activate"].bool != true || installed["active"].bool==true else{throw ShopdeckError.message("Plugin installation/activation could not be verified.")}
        let result:JSONValue = .object(["id":installed["id"],"name":.string(name),"version":installed["version"],"installedAt":installed["installedAt"],"active":installed["active"],"verified":.bool(true)])
        try checkpoint(operation.id,"installation",result);return result
    }
    private func plugin(_ shop:Shop,name:String)async throws->JSONValue {
        let response=try await client.adminRequest(shop,request:.init(method:"POST",path:"search/plugin",body:.object(["limit":.number(1),"filter":.array([.object(["type":.string("equals"),"field":.string("name"),"value":.string(name)])])])))
        guard let row=response["data"].array.first else{throw ShopdeckError.message("The uploaded plugin was not registered by Shopware.")};return row
    }
    private func createCampaign(_ operation:AutomationOperation,shop:Shop)async throws->JSONValue {
        var assets:[String:JSONValue]=[:]
        // Validate referenced products and the selected channel before creating any resource.
        _ = try await read(shop,entity:"sales-channel",id:operation.payload["sales_channel_id"].string ?? "")
        for section in operation.payload["sections"].array where section["type"].string=="product_slider" {for product in section["product_ids"].array{_ = try await read(shop,entity:"product",id:product.string ?? "")}}
        for file in operation.files{assets[file.id]=try await upload(file,operation:operation.id,shop:shop)}
        func substitute(_ value:JSONValue)->JSONValue{switch value{case .string(let text):if text.hasPrefix("asset:"),let asset=assets[String(text.dropFirst(6))]{return asset["id"]};return value;case .array(let items):return .array(items.map(substitute));case .object(let items):return .object(items.mapValues(substitute));default:return value}}
        let page=substitute(operation.payload["page"]),pageID=try Validation.entityID(page["id"].string ?? ""),landingID=try Validation.entityID(operation.payload["landing_page_id"].string ?? ""),channel=operation.payload["sales_channel_id"].string ?? "",publish=operation.payload["publish"].bool ?? false
        try checkpoint(operation.id,"cms_page",.object(["id":.string(pageID),"status":.string("creating")]))
        _ = try await client.executeAdminApproval(shop,request:.init(method:"POST",path:"cms-page",body:page))
        let saved=try await read(shop,entity:"cms-page",id:pageID,associations:.object(["sections":.object(["associations":.object(["blocks":.object(["associations":.object(["slots":.object([:])])])])])]))
        let expectedSlots=page["sections"].array.flatMap{$0["blocks"].array}.flatMap{$0["slots"].array}
        let actualSlots=saved["sections"].array.flatMap{$0["blocks"].array}.flatMap{$0["slots"].array}
        guard saved["name"]==page["name"],expectedSlots.count==actualSlots.count,expectedSlots.allSatisfy({expected in actualSlots.contains{actual in actual["id"]==expected["id"] && actual["type"]==expected["type"] && expected["config"].object?.allSatisfy{key,value in actual["config"][key]==value}==true}}) else{throw ShopdeckError.message("The saved CMS page does not match the approved sections and slot configuration.")}
        try checkpoint(operation.id,"cms_page",.object(["id":.string(pageID),"verified":.bool(true)]))
        let landing:JSONValue = .object(["id":.string(landingID),"name":page["name"],"url":.string("shopdeck-"+String(landingID.prefix(12))),"cmsPageId":.string(pageID),"active":.bool(publish),"salesChannels":.array([.object(["id":.string(channel)])])])
        try checkpoint(operation.id,"landing_page",.object(["id":.string(landingID),"status":.string("creating")]))
        _ = try await client.adminRequest(shop,request:.init(method:"POST",path:"landing-page",body:landing))
        let stored=try await read(shop,entity:"landing-page",id:landingID)
        guard stored["cmsPageId"].string==pageID,stored["active"].bool==publish else{throw ShopdeckError.message("The landing page assignment could not be verified.")}
        let admin=try ShopLinks.administration(shop).absoluteString+"#/sw/cms/detail/"+pageID
        var result:[String:JSONValue]=["cms_page_id":.string(pageID),"landing_page_id":.string(landingID),"admin_url":.string(admin),"published":.bool(publish),"stored_content_verified":.bool(true),"media":.array(Array(assets.values)),"storefront_verified":.bool(false)]
        if publish {
            let channelRow=try await read(shop,entity:"sales-channel",id:channel,associations:.object(["domains":.object([:])]))
            let urls=channelRow["domains"].array.compactMap{$0["url"].string}.compactMap{URL(string:$0)?.appendingPathComponent("landingPage/"+landingID)}
            result["storefront_urls"] = .array(urls.map{.string($0.absoluteString)})
            // No admin token is ever sent to storefront domains. Reachability is checked independently.
            let config=URLSessionConfiguration.ephemeral;config.timeoutIntervalForRequest=20;let session=URLSession(configuration:config,delegate:NoRedirectDelegate(),delegateQueue:nil)
            defer{session.invalidateAndCancel()}
            var reachable:[JSONValue]=[],httpChecks:[JSONValue]=[]
            for url in urls.prefix(10){
                guard var target=try? Validation.shopURL(url.absoluteString)else{continue}
                for _ in 0..<6 {
                    guard let (body,response)=try? await session.data(from:target),let http=response as? HTTPURLResponse else{break}
                    httpChecks.append(.object(["url":.string(target.absoluteString),"status":.number(Double(http.statusCode))]))
                    if http.statusCode==200,body.count>100{reachable.append(.string(target.absoluteString));break}
                    guard [301,302,303,307,308].contains(http.statusCode),let location=http.value(forHTTPHeaderField:"Location"),let next=URL(string:location,relativeTo:target)?.absoluteURL,next.host==url.host,next.port==url.port,!(target.scheme=="https" && next.scheme != "https"),let clean=try? Validation.shopURL(next.absoluteString)else{break}
                    target=clean
                }
            }
            result["storefront_checks"] = .array(httpChecks);result["reachable_urls"] = .array(reachable);result["storefront_verified"] = .bool(!reachable.isEmpty)
        }
        let receipt=JSONValue.object(result);try checkpoint(operation.id,"landing_page",receipt);return receipt
    }
    private func read(_ shop:Shop,entity:String,id:String,associations:JSONValue = .object([:]))async throws->JSONValue {
        let id=try Validation.entityID(id)
        let response=try await client.adminRequest(shop,request:.init(method:"POST",path:"search/"+entity,body:.object(["ids":.array([.string(id)]),"limit":.number(1),"associations":associations])))
        guard let value=response["data"].array.first else{throw ShopdeckError.message("Referenced "+entity+" was not found.")};return value
    }
}
