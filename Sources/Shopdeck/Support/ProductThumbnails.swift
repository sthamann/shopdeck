import AppKit
import ImageIO
import ShopdeckCore
@MainActor final class ProductThumbnails {
    static let shared=ProductThumbnails()
    private let cache=NSCache<NSString,NSImage>()
    private var tasks:[URL:Task<NSImage?,Never>]=[:]
    private let session:URLSession
    init(){cache.totalCostLimit=24*1024*1024;cache.countLimit=300;let configuration=URLSessionConfiguration.ephemeral;configuration.httpShouldSetCookies=false;configuration.timeoutIntervalForRequest=12;configuration.timeoutIntervalForResource=18;session=URLSession(configuration:configuration)}
    static func url(_ record:ShopRecord)->URL? {
        let media=record.data["cover"]["media"],thumbs=media["thumbnails"].array.sorted{($0["width"].number ?? 999)<($1["width"].number ?? 999)}
        let text=thumbs.first(where:{($0["width"].number ?? 0)>=80})?["url"].string ?? media["url"].string
        guard let text,var value=URLComponents(string:text),value.user==nil,value.password==nil else{return nil}
        if ShopLinks.isManagedLocal(record.shop),["localhost","127.0.0.1"].contains(value.host ?? ""),let base=URLComponents(string:record.shop.url){value.host=base.host;value.port=base.port;value.scheme=base.scheme}
        guard value.scheme=="https" || ShopLinks.isManagedLocal(record.shop) && value.scheme=="http" else{return nil};return value.url
    }
    func image(_ url:URL)async->NSImage? {
        if let value=cache.object(forKey:url.absoluteString as NSString){return value}
        if let task=tasks[url]{return await task.value}
        let task=Task<NSImage?,Never>{[session] in do{var request=URLRequest(url:url);request.httpShouldHandleCookies=false;let(data,response)=try await session.data(for:request);guard let http=response as? HTTPURLResponse,http.statusCode==200,data.count<=12*1024*1024 else{return nil};let image=await Task.detached(priority:.utility){()->CGImage? in guard let source=CGImageSourceCreateWithData(data as CFData,nil)else{return nil};return CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceThumbnailMaxPixelSize:100,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceShouldCacheImmediately:true] as CFDictionary)}.value;guard let image else{return nil};return NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height))}catch{return nil}}
        tasks[url]=task;let result=await task.value;tasks[url]=nil;if let result{cache.setObject(result,forKey:url.absoluteString as NSString,cost:Int(result.size.width*result.size.height*4))};return result
    }
}
@MainActor final class ProductThumbnailCell:NSTableCellView {
    private let picture=NSImageView()
    private var task:Task<Void,Never>?
    private var representedURL:URL?
    override init(frame:NSRect){super.init(frame:frame);picture.translatesAutoresizingMaskIntoConstraints=false;picture.imageScaling = .scaleProportionallyUpOrDown;picture.wantsLayer=true;picture.layer?.cornerRadius=5;picture.layer?.masksToBounds=true;addSubview(picture);NSLayoutConstraint.activate([picture.widthAnchor.constraint(equalToConstant:30),picture.heightAnchor.constraint(equalToConstant:30),picture.centerXAnchor.constraint(equalTo:centerXAnchor),picture.centerYAnchor.constraint(equalTo:centerYAnchor)])}
    required init?(coder:NSCoder){fatalError()}
    func configure(_ record:ShopRecord){let url=ProductThumbnails.url(record);guard representedURL != url || picture.image==nil else{return};representedURL=url;task?.cancel();picture.image=NSImage(systemSymbolName:"photo",accessibilityDescription:T("Produktbild"));picture.contentTintColor = .tertiaryLabelColor;guard let url else{return};task=Task{[weak self] in let image=await ProductThumbnails.shared.image(url);guard !Task.isCancelled,self?.representedURL==url else{return};if let image{self?.picture.contentTintColor=nil;self?.picture.image=image}}}
}
