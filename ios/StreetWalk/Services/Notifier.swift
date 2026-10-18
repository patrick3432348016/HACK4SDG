import Foundation
@preconcurrency import UserNotifications

/// A58 local notifications: thirty-minute departure reminder and meetup expiry, including while locked/backgrounded.
/// Suppress system banners in foreground and use checkAppointments in-app banners.
/// Reliable remote neighbor-departure push needs backend/APNs; a local demo cannot establish it.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Request notifications only when needed for enabled neighbor reminders or a meetup; ask once, then defer to system settings.
    func requestIfNeeded() {
        let c = UNUserNotificationCenter.current()
        c.getNotificationSettings { s in
            guard s.authorizationStatus == .notDetermined else { return }
            c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// Previously scheduled content; do not reschedule identical notifications.
    private var lastPlan: [NotificationPlan.Item]?
    /// Serialize clear-and-reschedule operations so concurrent syncs cannot retain cancelled-meetup reminders.
    private let queue = DispatchQueue(label: "streetwalk.notifier", qos: .utility)

    /// Rebuild pending notifications from current meetups, clearing this app's previous meetup schedule first.
    /// Run system notification calls on a background serial queue to avoid blocking the UI.
    func sync(_ items: [NotificationPlan.Item]) {
        let plan = items.filter { $0.at.timeIntervalSinceNow > 1 }
        guard plan != lastPlan else { return }
        lastPlan = plan
        if LaunchArgs.has("-logNotifications") { plan.forEach { print("[notify] \($0.id) \($0.at) \($0.body)") } }
        let title = L.t("街坊行", "街坊行", "StreetWalk")   // Choose the language on the main thread.
        queue.async {
            let c = UNUserNotificationCenter.current()
            c.removeAllPendingNotificationRequests()
            for it in plan {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = it.body
                content.sound = .default
                // Use relative countdowns independent of device timezone; reschedule after every meetup change.
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, it.at.timeIntervalSinceNow), repeats: false)
                c.add(UNNotificationRequest(identifier: it.id, content: content, trigger: trigger))
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }
}

/// Pure, unit-testable notification selection.
enum NotificationPlan {
    struct Item: Equatable {
        var id: String
        var at: Date
        var body: String
    }

    static let remindBefore: TimeInterval = 30 * 60
    /// Match checkAppointments: expire one hour after the scheduled time.
    static let expireAfter: TimeInterval = 60 * 60

    static func items(_ appointments: [Appointment], now: Date,
                      partner: (String) -> String, place: (String) -> String) -> [Item] {
        var out: [Item] = []
        for a in appointments where a.isOpen {
            let who = partner(a.partnerID), spot = place(a.landmarkID)
            let remindAt = a.date.addingTimeInterval(-remindBefore)
            if a.status == .accepted, !a.reminded, remindAt > now {
                out.append(Item(id: "appt-\(a.id.uuidString)-remind", at: remindAt, body: L.t("30 分鐘後約咗\(who)喺\(spot)。", "30 分钟后和\(who)约在\(spot)。", "In 30 min: meet \(who) at \(spot).")))
            }
            let expireAt = a.date.addingTimeInterval(expireAfter)
            if expireAt > now {
                let hour = AppStore.clockLabel(a.date)   // Include explicit minutes, such as 16:45.
                out.append(Item(id: "appt-\(a.id.uuidString)-expire", at: expireAt, body: L.t("同\(who)\(hour)喺\(spot)嘅約過咗時間，收埋咗。", "和\(who)\(hour)在\(spot)的约已过时间，已收起。", "The \(hour) walk plan with \(who) at \(spot) has passed. Cleared.")))
            }
        }
        return out
    }
}
