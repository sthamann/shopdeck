import SwiftUI
import Combine
#if !APP_STORE
import Sparkle

@MainActor final class AppUpdater:ObservableObject {
    static let shared=AppUpdater()
    @Published private(set) var canCheck=false
    let configured:Bool
    private let controller:SPUStandardUpdaterController
    private var observation:AnyCancellable?
    private init() {
        let feed=Bundle.main.object(forInfoDictionaryKey:"SUFeedURL") as? String ?? ""
        let key=Bundle.main.object(forInfoDictionaryKey:"SUPublicEDKey") as? String ?? ""
        configured=URL(string:feed)?.scheme == "https" && !key.isEmpty
        controller=SPUStandardUpdaterController(startingUpdater:false,updaterDelegate:nil,userDriverDelegate:nil)
        observation=controller.updater.publisher(for:\.canCheckForUpdates).receive(on:RunLoop.main).sink { [weak self] value in self?.canCheck=value }
        if configured {controller.startUpdater()}
    }
    var automatic:Bool {get{controller.updater.automaticallyChecksForUpdates}set{controller.updater.automaticallyChecksForUpdates=newValue}}
    func check(){guard configured else{return};controller.checkForUpdates(nil)}
}
#endif
struct AppUpdateSettings:View {
    #if !APP_STORE
    @ObservedObject private var updater=AppUpdater.shared
    #endif
    var body:some View {
        Section(T("Shopdeck Updates")) {
            #if APP_STORE
            Label(T("Updates kommen über den Mac App Store."), systemImage:"app.badge")
            #else
            if updater.configured {
                Toggle(T("Neue App Versionen automatisch suchen"),isOn:Binding(get:{updater.automatic},set:{updater.automatic=$0}))
                Button(T("Nach Shopdeck Updates suchen …")){updater.check()}.disabled(!updater.canCheck)
            } else {Label(T("Automatische App Updates sind vorbereitet."),systemImage:"checkmark.shield");Text(T("Für die Veröffentlichung wird noch die Adresse des Update Feeds hinterlegt. Diese Version lädt keine App Updates.")).font(.caption).foregroundStyle(.secondary)}
            #endif
        }
    }
}
struct AppUpdateMenuItem:View {
    #if !APP_STORE
    @ObservedObject private var updater=AppUpdater.shared
    var body:some View {Button(T("Nach Shopdeck Updates suchen …")){updater.check()}.disabled(!updater.configured || !updater.canCheck)}
    #else
    var body:some View { EmptyView() }
    #endif
}
