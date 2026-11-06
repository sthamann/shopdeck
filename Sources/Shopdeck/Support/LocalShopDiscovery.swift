import Foundation
import ShopdeckCore
@MainActor enum LocalShopDiscovery {
    static func suggest(model:AppModel)async->(name:String,port:Int?) {
        var names=model.workspace.shops.map(\.name),reserved=Set(model.workspace.shops.compactMap{URL(string:$0.url)?.port})
        if let docker=LocalCommand.docker,let text=try? await LocalCommand.run(docker,["ps","-a","--format","{{json .}}"],timeout:4){for line in text.split(separator:"\n"){if let row=try? JSONDecoder().decode(JSONValue.self,from:Data(line.utf8)){if let name=row["Names"].string{names.append(name)};let ports=row["Ports"].string ?? "";let regex=try? NSRegularExpression(pattern:":([0-9]+)->");for match in regex?.matches(in:ports,range:NSRange(ports.startIndex...,in:ports)) ?? [] {if let range=Range(match.range(at:1),in:ports),let value=Int(ports[range]){reserved.insert(value)}}}}}
        return (LocalShopSuggestion.name(existing:names,prefix:T("Shopware Lokal")),LocalShopSuggestion.port(reserved:reserved))
    }
}
