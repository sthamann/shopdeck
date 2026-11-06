import SwiftUI
import ShopdeckCore

struct BookmarkMenu: View {
    var model: AppModel
    var body: some View {
        let entries = model.bookmarks
        let groups = Dictionary(grouping: entries, by: \.shopID)
        return Menu {
            if entries.isEmpty { Text(T("Öffne einen Datensatz und klicke auf den Stern.")) }
            ForEach(model.workspace.shops.filter { groups[$0.id] != nil }) { shop in
                Section(shop.name) {
                    ForEach(groups[shop.id] ?? []) { item in
                        Button { model.openBookmark(item) } label: { Label(item.title, systemImage: item.entity == "order" ? "bag" : item.entity == "customer" ? "person" : "shippingbox") }
                    }
                }
            }
        } label: { Label(T("Lesezeichen"), systemImage: model.bookmarks.isEmpty ? "star" : "star.fill").labelStyle(.iconOnly) }.menuStyle(.borderlessButton).fixedSize().help(T("Lesezeichen")).accessibilityLabel(T("Lesezeichen"))
    }
}
