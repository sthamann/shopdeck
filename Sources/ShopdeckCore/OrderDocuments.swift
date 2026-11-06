import Foundation
import CoreGraphics
import CoreText

public struct OrderDocument: Identifiable, Equatable, Sendable {
    public let shop: Shop
    public let documentID: String
    public let orderID: String
    public let type: String
    public let number: String
    public let createdAt: String?
    let deepLinkCode: String
    public var id: String { shop.id.uuidString + ":" + documentID }
    public init(shop: Shop, data: JSONValue) throws {
        self.shop = shop; documentID = try Validation.entityID(data["id"].string ?? ""); orderID = try Validation.entityID(data["orderId"].string ?? "")
        type = data["documentType"]["technicalName"].string ?? "document"
        number = data["config"]["documentNumber"].string ?? String(documentID.prefix(8))
        createdAt = data["createdAt"].string; deepLinkCode = data["deepLinkCode"].string ?? ""
    }
    public var filename: String {
        let raw = type + "-" + number
        let safe = raw.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0) ? String($0) : "_" }.joined()
        var result = ""
        for scalar in safe.unicodeScalars { if result.utf8.count + String(scalar).utf8.count > 140 { break }; result.unicodeScalars.append(scalar) }
        return result + ".pdf"
    }
    public var archiveDirectory: String {
        var label = ""
        for scalar in shop.name.unicodeScalars {
            let piece = CharacterSet.alphanumerics.contains(scalar) || "-_".unicodeScalars.contains(scalar) ? String(scalar) : "_"
            if label.utf8.count + piece.utf8.count > 60 { break }; label += piece
        }
        return label + "-" + shop.id.uuidString
    }
    public func downloadPath() throws -> String {
        guard deepLinkCode.range(of: "^[A-Za-z0-9_-]{16,128}$", options: .regularExpression) != nil else { throw ShopdeckError.message("Dieses Dokument hat keinen gültigen Downloadschlüssel. Öffne es in der Shopware Administration.") }
        return "_action/document/" + documentID + "/" + deepLinkCode
    }
    public static func demoPDF(number: String) -> Data {
        let data = NSMutableData(); var box = CGRect(x: 0, y: 0, width: 595, height: 842)
        guard let consumer = CGDataConsumer(data: data), let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        context.beginPDFPage(nil)
        func text(_ value: String, _ size: CGFloat, _ y: CGFloat) {
            let string = NSAttributedString(string: value, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, size, nil)])
            context.textPosition = CGPoint(x: 55, y: y); CTLineDraw(CTLineCreateWithAttributedString(string), context)
        }
        context.setFillColor(CGColor(gray: 0.12, alpha: 1))
        text("shopdeck", 30, 766); text("SAMPLE DOCUMENT", 21, 700); text(number, 16, 668)
        text("Demo data. This is not a real invoice.", 12, 620)
        text("Preview existing Shopware invoices and delivery notes", 12, 570)
        text("without leaving your workspace.", 12, 548)
        context.endPDFPage(); context.closePDF(); return data as Data
    }
}
public struct OrderDocumentPage: Sendable { public var documents: [OrderDocument]; public var total: Int }

final class DocumentDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var exceeded = false
    let maximum: Int64 = 32 * 1024 * 1024
    var tooLarge: Bool { lock.lock(); defer { lock.unlock() }; return exceeded }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > maximum || totalBytesExpectedToWrite > maximum { lock.lock(); exceeded = true; lock.unlock(); downloadTask.cancel() }
    }
}
