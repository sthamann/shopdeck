import Foundation
import ShopdeckCore

enum Language {
    static let all = [("de", "Deutsch"), ("en", "English"), ("nl", "Nederlands"), ("es", "Español"), ("fr", "Français"), ("it", "Italiano")]
    static var current: String { UserDefaults.standard.string(forKey: "language").flatMap{AppLanguage.supported.contains($0) ? $0:nil} ?? AppLanguage.initial() }
    static let translations: [String: [String]] = {
        #if SWIFT_PACKAGE
        let resources = Bundle.module
        #else
        let resources = Bundle.main
        #endif
        guard let file = resources.url(forResource: "Localizations", withExtension: "tsv"), let text = try? String(contentsOf: file, encoding: .utf8) else { return [:] }
        var result: [String: [String]] = [:]
        for line in text.split(separator: "\n") { let columns = line.components(separatedBy: "\t"); if columns.count == 6 { result[columns[0]] = Array(columns.dropFirst()) } }
        return result
    }()
    static func text(_ key: String) -> String {
        if current == "de" {
            let labels = ["name": "Name", "description": "Beschreibung", "stock": "Bestand", "active": "Aktiv", "pending": "Wartet auf Freigabe", "applying": "Wird übernommen", "applied": "Übernommen", "rejected": "Abgelehnt", "needs_review": "Zu prüfen", "open": "Offen", "in_progress": "In Bearbeitung", "completed": "Abgeschlossen", "cancelled": "Storniert"]
            return labels[key] ?? key
        }
        guard current != "de", let index = all.firstIndex(where: { $0.0 == current }), let values = translations[key.replacingOccurrences(of: "\n", with: "\\n")], values.count >= index else { return key }
        return values[index - 1].replacingOccurrences(of: "\\n", with: "\n")
    }
}
func T(_ key: String) -> String { Language.text(key) }

extension JSONValue {var localizedDisplayString:String{if let number{return number.formatted(.number.locale(Locale(identifier:Language.current)))};return displayString}}
