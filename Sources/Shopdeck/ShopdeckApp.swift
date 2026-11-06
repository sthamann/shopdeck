import SwiftUI
import UserNotifications
import ShopdeckCore

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true); UNUserNotificationCenter.current().delegate = self }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        guard let id = response.notification.request.content.userInfo["followUpID"] as? String, UUID(uuidString: id) != nil else { completionHandler(); return }
        Task { @MainActor in UserDefaults.standard.set(id, forKey: "pendingFollowUpToOpen"); NotificationCenter.default.post(name: .shopdeckOpenFollowUp, object: id); completionHandler() }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
}
@main struct ShopdeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @LocalState<AppModel> private var model = AppModel()
    @AppStorage("language") private var language = AppLanguage.initial()
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("showMenuBar") private var showMenuBar = false
    private var colorScheme: ColorScheme? { appearance == "dark" ? .dark : appearance == "light" ? .light : nil }
    init(){UserDefaults.standard.register(defaults:["language":AppLanguage.initial()])}
    var body: some Scene {
        Window("Shopdeck", id: "main") {
            WorkspaceShell(root: model).environment(\.locale, Locale(identifier: language)).tint(Theme.blue).preferredColorScheme(colorScheme)
                .frame(minWidth: 1080, minHeight: 700)
                .task { await model.prepareLocalTestIfRequested(); model.startMonitoring(); await model.reconcileReminders(); await model.refresh() }
                .onChange(of: model.followUps) { _, _ in Task { await model.reconcileReminders() } }
                .onChange(of: model.workspace.shops) { _, _ in Task { await model.reconcileReminders() } }
                .task { while !Task.isCancelled { model.reload(); try? await Task.sleep(for: .seconds(3)); if Task.isCancelled { break } } }
        }.defaultSize(width: 1280, height: 850).windowStyle(.hiddenTitleBar)
            .commands {
                CommandGroup(after:.appInfo){AppUpdateMenuItem()}
                CommandGroup(replacing: .newItem) { Button(T("Neuer Tab")) { appAction("newTab") }.keyboardShortcut("t"); Button(T("Geschlossenen Tab wieder öffnen")) { appAction("reopenTab") }.keyboardShortcut("t", modifiers: [.command, .shift]); Button(T("Shop hinzufügen")) { appAction("add") }.keyboardShortcut("n") }
                CommandMenu("Shopdeck") { Button(T("Schnellsuche")) { appAction("search") }.keyboardShortcut("k"); Button(T("Aktualisieren")) { appAction("refresh") }.keyboardShortcut("r"); Button("Codex & Claude") { appAction("ai") }.keyboardShortcut("k", modifiers: [.command, .shift]) }
            }
        MenuBarExtra("Shopdeck", systemImage:"bag.circle", isInserted:$showMenuBar) { MenuBarCommerceView(model:model).tint(Theme.blue).preferredColorScheme(colorScheme) }.menuBarExtraStyle(.window)
        Settings { AppSettingsView(model: model).tint(Theme.blue).preferredColorScheme(colorScheme) }
    }
}
