import SwiftUI
import Observation
import ShopdeckCore

private struct ShopWorkspaceActionKey: EnvironmentKey { static let defaultValue: (Shop?, Bool) -> Void = { _,_ in } }
extension EnvironmentValues { var openShopWorkspace: (Shop?, Bool) -> Void { get { self[ShopWorkspaceActionKey.self] } set { self[ShopWorkspaceActionKey.self] = newValue } } }
@MainActor @Observable final class ShopWorkspace: Identifiable {
    let id = UUID()
    let model: AppModel
    init(model: AppModel) { self.model = model }
    var title: String { model.selectedShop.map{$0.name+" · "+model.destination.title} ?? model.destination.title }
}
struct WorkspaceShell: View {
    var root: AppModel
    @AppStorage("onboardingCompleted") private var onboardingCompleted=false
    @LocalState<Bool> private var onboarding=false
    @LocalState<[ShopWorkspace]> private var tabs: [ShopWorkspace] = []
    @LocalState<UUID?> private var selected: UUID? = nil
    @LocalState<UUID?> private var secondary: UUID? = nil
    private var active: ShopWorkspace? { tabs.first { $0.id == selected } ?? tabs.first }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                ScrollView(.horizontal) { HStack(spacing: 6) { ForEach(tabs) { tab in
                    HStack(spacing: 9) { Image(systemName: tab.model.destination.icon).foregroundStyle(Theme.blue); Button(tab.title) { selected = tab.id; if secondary == tab.id { secondary = nil } }.buttonStyle(.plain).lineLimit(1); if tabs.count > 1 { Button { close(tab.id) } label: { Image(systemName:"xmark").font(.system(size:9,weight:.semibold)) }.buttonStyle(.plain).help(T("Tab schließen")) } }.font(.system(size:12,weight:.medium)).padding(.horizontal,13).padding(.vertical,9).background(active?.id == tab.id ? Theme.blue.opacity(0.13) : Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:8)).contextMenu { Button(T("Nebeneinander anzeigen")) { if active?.id != tab.id { secondary=tab.id } }; Button(T("Tab schließen")) { close(tab.id) }.disabled(tabs.count==1) }
                } } }.scrollIndicators(.hidden)
                Button { open(nil, split:false) } label: { Image(systemName:"plus") }.buttonStyle(.borderless).help(T("Neuer Tab") + " · ⌘T")
                Button { if secondary != nil { secondary=nil } else if let other=tabs.first(where:{$0.id != active?.id}) { secondary=other.id } else { open(active?.model.selectedShop,split:true) } } label: { Image(systemName:"rectangle.split.2x1") }.buttonStyle(.borderless).help(T("Nebeneinander anzeigen"))
            }.padding(.horizontal,16).padding(.top,9).padding(.bottom,8).background(.bar)
            Divider()
            HSplitView {
                if let active { ContentView(model:active.model).frame(minWidth:secondary == nil ? 900 : 650) }
                if let split=tabs.first(where:{$0.id == secondary}),split.id != active?.id { ContentView(model:split.model,showSidebar:false).frame(minWidth:480) }
            }
        }.environment(\.openShopWorkspace,{ shop,split in open(shop,split:split) })
            .sheet(isPresented:$onboarding){OnboardingView(model:root){openAI in onboardingCompleted=true;onboarding=false;if openAI{root.destination = .ai}}}
            .onAppear {if root.workspace.shops.isEmpty && !onboardingCompleted{onboarding=true}; if tabs.isEmpty { let first=ShopWorkspace(model:root);tabs=[first];selected=first.id } }
            .onReceive(NotificationCenter.default.publisher(for:.shopdeckAction)) { event in
                if event.object as? String == "onboard"{onboarding=true;return}
                guard let model=active?.model else{return}
                switch event.object as? String { case "newTab":open(nil,split:false);case "search":model.showingCommandPalette=true;case "add":model.showingAddShop=true;case "refresh":Task{await model.refresh()};case "ai":model.destination = .ai;case "dashboard":model.destination = .overview;default:break }
            }
            .onOpenURL { url in if url.scheme=="shopdeck" { active?.model.destination = .overview;Task{await active?.model.refresh()} } }
            .task { while !Task.isCancelled { for tab in tabs {tab.model.reload()};try? await Task.sleep(for:.seconds(3)) } }
            .background(Button("") { cycle(1) }.keyboardShortcut("]",modifiers:[.command,.shift]).hidden())
            .background(Button("") { cycle(-1) }.keyboardShortcut("[",modifiers:[.command,.shift]).hidden())
            .background(Button("") { if let active,tabs.count>1 { close(active.id) } }.keyboardShortcut("w").disabled(tabs.count<2).hidden())
    }
    private func open(_ shop:Shop?,split:Bool) {
        let model=AppModel(); model.selectedShopID=shop?.id;model.destination=shop == nil ? .overview : .admin
        let tab=ShopWorkspace(model:model);tabs.append(tab)
        if split { secondary=tab.id } else { selected=tab.id }
        Task { await model.refresh() }
    }
    private func close(_ id:UUID) { guard tabs.count>1 else{return};tabs.removeAll{$0.id==id};if secondary==id{secondary=nil};if selected==id{selected=tabs.first?.id} }
    private func cycle(_ offset:Int) { guard let active,let index=tabs.firstIndex(where:{$0.id==active.id}),!tabs.isEmpty else{return};selected=tabs[(index+offset+tabs.count)%tabs.count].id;if secondary==selected{secondary=nil} }
}
