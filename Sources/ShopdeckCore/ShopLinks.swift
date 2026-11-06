import Foundation

public enum ShopLinks {
    public static func isManagedLocal(_ shop:Shop)->Bool{shop.containerName?.hasPrefix("shopdeck-")==true && ["localhost","127.0.0.1","::1"].contains(URL(string:shop.url)?.host ?? "")}
    public static func administration(_ shop: Shop) throws -> URL {
        try Validation.shopURL(shop.url).appendingPathComponent("admin", isDirectory: true)
    }
}
