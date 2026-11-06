import Foundation
import UserNotifications
import ShopdeckCore

actor FollowUpNotifications {
    static let shared = FollowUpNotifications()
    private var running = false
    private var latest: ([RecordFollowUp], [Shop])?
    func synchronize(items: [RecordFollowUp], shops: [Shop]) async -> String? {
        latest = (items, shops)
        guard !running else { return nil }
        running = true; defer { running = false }
        var issue: String?
        while let next = latest { latest = nil; issue = await apply(items: next.0, shops: next.1) }
        return issue
    }
    private func apply(items: [RecordFollowUp], shops: [Shop]) async -> String? {
        let center = UNUserNotificationCenter.current(), plans = FollowUpReminder.plan(items: items, shops: shops)
        let settings = await center.notificationSettings()
        let pending = await center.pendingNotificationRequests()
        let wanted = Set(plans.map(\.id))
        let obsolete = pending.filter { $0.identifier.hasPrefix(FollowUpReminder.prefix) && !wanted.contains($0.identifier) }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: obsolete)
        let completed = items.filter { $0.completedAt != nil || $0.reminderEnabled != true }.map { FollowUpReminder.prefix + $0.id.uuidString }
        center.removeDeliveredNotifications(withIdentifiers: completed)
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return plans.isEmpty ? nil : T("Erlaube Shopdeck Mitteilungen in den macOS Systemeinstellungen.") }
        let existing = Dictionary(uniqueKeysWithValues: pending.map { ($0.identifier, $0) })
        for plan in plans {
                let title = T("Wiedervorlage fällig"), body = plan.shopName + " · " + plan.recordTitle
            if let request = existing[plan.id], let trigger = request.trigger as? UNCalendarNotificationTrigger, let date = trigger.nextTriggerDate(), abs(date.timeIntervalSince(plan.dueAt)) < 1, request.content.title == title, request.content.body == body { continue }
            let content = UNMutableNotificationContent(); content.title = title; content.body = body
            content.userInfo = ["followUpID": plan.followUpID.uuidString]
            if UserDefaults.standard.object(forKey: "notificationSound") as? Bool != false { content.sound = .default }
            var parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: plan.dueAt); parts.timeZone = .current
            do { try await center.add(UNNotificationRequest(identifier: plan.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))) }
            catch { return T("Die Erinnerung konnte nicht geplant werden.") + " " + error.localizedDescription }
        }
        return nil
    }
}
extension Notification.Name { static let shopdeckOpenFollowUp = Notification.Name("ShopdeckOpenFollowUp") }
