import Foundation
public enum AppLanguage {
    public static let supported=["de","en","nl","es","fr","it"]
    public static func initial(preferred:[String]=Locale.preferredLanguages)->String {let primary=(preferred.first ?? "en").replacingOccurrences(of:"_",with:"-").split(separator:"-").first.map{String($0).lowercased()} ?? "en";return supported.contains(primary) ? primary:"en"}
}
