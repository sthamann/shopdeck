import SwiftUI
import UniformTypeIdentifiers

struct ShopDropDelegate: DropDelegate {
    let model: AppModel
    var beforeShop: UUID?
    var group: UUID?
    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.text]) }
    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let raw = value as? String else { return }
            Task { @MainActor in
                if raw.hasPrefix("group:"), let id = UUID(uuidString: String(raw.dropFirst(6))), let group, id != group {
                    model.mutate { state in guard let from = state.groups.firstIndex(where: { $0.id == id }) else { return }; let moved = state.groups.remove(at: from); let target = state.groups.firstIndex(where: { $0.id == group }) ?? state.groups.endIndex; state.groups.insert(moved, at: target) }
                } else if let id = UUID(uuidString: raw), id != beforeShop { model.moveShop(id, before: beforeShop, group: group) }
            }
        }
        return true
    }
}
