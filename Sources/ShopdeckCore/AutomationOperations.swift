import Foundation
import CryptoKit
import ImageIO

/// Approval records contain immutable copies of files, never credentials or executable local commands.
public struct AutomationOperation:Codable,Identifiable,Sendable {
    public var id=UUID()
    public var shopID:UUID
    public var shopName:String
    public var kind:String
    public var title:String
    public var reason:String
    public var payload:JSONValue
    public var files:[StagedAsset]=[]
    public var status="pending"
    public var createdAt=Date()
    public var completedAt:Date?
    public var checkpoints:[String:JSONValue]=[:]
    public var result:JSONValue?
    public var error:String?
    public init(shop:Shop,kind:String,title:String,reason:String,payload:JSONValue,files:[StagedAsset]=[]){shopID=shop.id;shopName=shop.name;self.kind=kind;self.title=String(title.prefix(200));self.reason=String(reason.prefix(2000));self.payload=payload;self.files=files}
}
public struct AutomationQueue:Codable,Sendable {public var operations:[AutomationOperation]=[];public init(){}}
public struct StagedAsset:Codable,Identifiable,Sendable {
    public var id:String
    public var name:String
    public var fileExtension:String
    public var mimeType:String
    public var byteCount:Int
    public var sha256:String
    public var metadata:JSONValue
}
extension WorkspaceStore {
    public func readAutomationQueue()throws->AutomationQueue{try locked{try readLocalFile("automation-operations.json",fallback:AutomationQueue())}}
    @discardableResult public func updateAutomationQueue<T>(_ change:(inout AutomationQueue)throws->T)throws->T{try locked{var queue=try readLocalFile("automation-operations.json",fallback:AutomationQueue());let result=try change(&queue);try writeLocalFile(queue,name:"automation-operations.json");return result}}
    public func stagedPreviewURL(_ asset:StagedAsset)->URL{directory.appendingPathComponent("staged-assets").appendingPathComponent(asset.id+".preview.png")}
    public func stagedURL(_ asset:StagedAsset)->URL{directory.appendingPathComponent("staged-assets").appendingPathComponent(asset.id)}
    public func stagedData(_ asset:StagedAsset)throws->Data{
        guard UUID(uuidString:asset.id) != nil else{throw ShopdeckError.message("Invalid staged asset reference.")}
        let data=try Data(contentsOf:stagedURL(asset));guard data.count==asset.byteCount,Self.hash(data)==asset.sha256 else{throw ShopdeckError.message("The approved file has changed. Prepare a new request.")};return data
    }
    public func stageFile(_ path:String,plugin:Bool=false)throws->StagedAsset {
        let url=URL(fileURLWithPath:path),info=try url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
        guard path.hasPrefix("/"),info.isRegularFile==true,info.isSymbolicLink != true,let size=info.fileSize,size>0,size<=(plugin ? 100_000_000:20_000_000) else{throw ShopdeckError.message("Choose a regular local image up to 20 MB or a plugin ZIP up to 100 MB.")}
        let data=try Data(contentsOf:url);guard data.count==size else{throw ShopdeckError.message("The file changed while preparing it.")}
        let ext=url.pathExtension.lowercased(),mime:String,metadata:JSONValue
        if plugin {
            guard ext=="zip" else{throw ShopdeckError.message("A Shopware plugin ZIP is required.")}
            let inspection=directory.appendingPathComponent("inspect-"+UUID().uuidString+".zip")
            try data.write(to:inspection,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:inspection.path);defer{try? FileManager.default.removeItem(at:inspection)}
            metadata=try PluginPackage.inspect(inspection,data:data);mime="application/zip"
        } else {
            let types=["png":"public.png","jpg":"public.jpeg","jpeg":"public.jpeg","webp":"org.webmproject.webp","gif":"com.compuserve.gif"]
            guard let expected=types[ext],let image=CGImageSourceCreateWithData(data as CFData,nil),let type=CGImageSourceGetType(image) as String?,type==expected,let properties=CGImageSourceCopyPropertiesAtIndex(image,0,nil) as? [String:Any],let width=properties[kCGImagePropertyPixelWidth as String] as? Int,let height=properties[kCGImagePropertyPixelHeight as String] as? Int,width>0,height>0,width<=20_000,height<=20_000,width*height<=100_000_000 else{throw ShopdeckError.message("Use a valid PNG, JPEG, WebP or GIF image with at most 100 megapixels.")}
            mime=ext=="png" ? "image/png":ext=="webp" ? "image/webp":ext=="gif" ? "image/gif":"image/jpeg"
            metadata = .object(["width":.number(Double(width)),"height":.number(Double(height))])
        }
        let asset=StagedAsset(id:UUID().uuidString,name:String(url.deletingPathExtension().lastPathComponent.prefix(100)),fileExtension:ext,mimeType:mime,byteCount:size,sha256:Self.hash(data),metadata:metadata)
        let folder=directory.appendingPathComponent("staged-assets");try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]);try data.write(to:stagedURL(asset),options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:stagedURL(asset).path)
        if !plugin,let source=CGImageSourceCreateWithData(data as CFData,nil),let thumbnail=CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:800,kCGImageSourceCreateThumbnailWithTransform:true] as CFDictionary),let destination=CGImageDestinationCreateWithURL(stagedPreviewURL(asset) as CFURL,"public.png" as CFString,1,nil){CGImageDestinationAddImage(destination,thumbnail,nil);if CGImageDestinationFinalize(destination){try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:stagedPreviewURL(asset).path)}}
        return asset
    }
    private static func hash(_ data:Data)->String{SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
}

public enum PluginPackage {
    public static func inspect(_ url:URL,data:Data)throws->JSONValue {
        func fail()throws->Never{throw ShopdeckError.message("Invalid plugin ZIP. Paths, links, encryption and expansion limits are checked before upload.")}
        func u16(_ p:Int)->Int{Int(data[p])|Int(data[p+1])<<8}
        func u32(_ p:Int)->Int{u16(p)|u16(p+2)<<16}
        guard data.count>=22 else{try fail()}
        guard let end=(max(0,data.count-65557)...data.count-22).reversed().first(where:{u32($0)==0x06054b50 && $0+22+u16($0+20)==data.count}),u16(end+4)==0,u16(end+6)==0,u16(end+8)==u16(end+10),u16(end+10)>0,u16(end+10)<=20000 else{try fail()}
        let count=u16(end+10),offset=u32(end+16);guard offset>=0,offset<end else{try fail()}
        var pos=offset,total=0,entries:[String]=[],seen=Set<String>()
        for _ in 0..<count {
            guard pos+46<=end,u32(pos)==0x02014b50 else{try fail()}
            let flags=u16(pos+8),compressed=u32(pos+20),expanded=u32(pos+24),length=u16(pos+28),extra=u16(pos+30),comment=u16(pos+32),mode=u32(pos+38)>>16
            guard pos+46+length+extra+comment<=end,flags&1==0,[0,8].contains(u16(pos+10)),expanded<500_000_000,(mode&0xf000) != 0xa000,let name=String(data:data.subdata(in:pos+46..<pos+46+length),encoding:.utf8),!name.hasPrefix("/"),!name.contains("\\"),!name.contains(":"),!name.split(separator:"/").contains(".."),!name.contains("\0"),seen.insert(name).inserted else{try fail()}
            total+=expanded;guard total<=500_000_000,expanded<=max(1,compressed)*500 else{try fail()}
            if name.hasSuffix("composer.json"),name.split(separator:"/").count<=2,expanded<=128_000{entries.append(name)}
            pos+=46+length+extra+comment
        }
        guard pos==offset+u32(end+12),entries.count==1 else{throw ShopdeckError.message("The ZIP must contain one plugin composer.json at its root or in one top level directory.")}
        let process=Process(),pipe=Pipe();process.executableURL=URL(fileURLWithPath:"/usr/bin/unzip");process.arguments=["-p",url.path,entries[0]];process.standardOutput=pipe;process.standardError=FileHandle.nullDevice;try process.run();let raw=pipe.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
        guard process.terminationStatus==0,raw.count<=128_000,let composer=try? JSONDecoder().decode(JSONValue.self,from:raw),composer["type"].string=="shopware-platform-plugin",!(composer["name"].string ?? "").isEmpty,!(composer["description"].string ?? "").isEmpty,let name=composer["extra"]["shopware-plugin-class"].string?.split(separator:"\\").last.map(String.init),name.range(of:"^[A-Za-z][A-Za-z0-9_]{1,99}$",options:.regularExpression) != nil,let version=composer["version"].string,let requires=composer["require"]["shopware/core"].string else{throw ShopdeckError.message("The package needs type shopware-platform-plugin, a plugin class, version and shopware/core requirement.")}
        return .object(["technicalName":.string(name),"version":.string(version),"coreConstraint":.string(requires),"composerName":composer["name"],"entries":.number(Double(count)),"unpackedBytes":.number(Double(total))])
    }
}
