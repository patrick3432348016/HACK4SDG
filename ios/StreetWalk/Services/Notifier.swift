import Foundation
@preconcurrency import UserNotifications

/// A58 本地通知：约会出发前 30 分钟提醒、过咗期。App 锁屏 / 喺背景都收到。
/// App 喺前台时唔弹系统通知，照用 App 自己嘅横幅（checkAppointments）。
/// 街坊出门提醒要等后端推送（APNs），单机演示做唔到。
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// 要用时先问（有街坊开咗出门提醒、或者有约会，见 AppStore.requestNotificationsIfReady）；只问一次，之后由系统设定管。
    func requestIfNeeded() {
        let c = UNUserNotificationCenter.current()
        c.getNotificationSettings { s in
            guard s.authorizationStatus == .notDetermined else { return }
            c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// 上次排咗乜（一样就唔再郁系统通知）。
    private var lastPlan: [NotificationPlan.Item]?
    /// 串行队列：两次 sync 嘅「清走、再排」唔会交错（唔会留低已取消约会嘅提醒）。
    private let queue = DispatchQueue(label: "streetwalk.notifier", qos: .utility)

    /// 按而家嘅约会重排全部通知（本 App 只有约会通知，所以先全部清走）。
    /// 系统调用放去背景串行队列做，唔好阻住界面。
    func sync(_ items: [NotificationPlan.Item]) {
        let plan = items.filter { $0.at.timeIntervalSinceNow > 1 }
        guard plan != lastPlan else { return }
        lastPlan = plan
        if LaunchArgs.has("-logNotifications") { plan.forEach { print("[notify] \($0.id) \($0.at) \($0.body)") } }
        queue.async {
            let c = UNUserNotificationCenter.current()
            c.removeAllPendingNotificationRequests()
            for it in plan {
                let content = UNMutableNotificationContent()
                content.title = "街坊行"
                content.body = it.body
                content.sound = .default
                // 用倒数（唔受手机时区影响）；每次约会有改动都会重排
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

/// 要排边几个通知（纯逻辑，可单测）。
enum NotificationPlan {
    struct Item: Equatable {
        var id: String
        var at: Date
        var body: String
    }

    static let remindBefore: TimeInterval = 30 * 60
    /// 同 checkAppointments 一样：过咗约定时间一个钟当过期。
    static let expireAfter: TimeInterval = 60 * 60

    static func items(_ appointments: [Appointment], now: Date,
                      partner: (String) -> String, place: (String) -> String) -> [Item] {
        var out: [Item] = []
        for a in appointments where a.isOpen {
            let who = partner(a.partnerID), spot = place(a.landmarkID)
            let remindAt = a.date.addingTimeInterval(-remindBefore)
            if a.status == .accepted, !a.reminded, remindAt > now {
                out.append(Item(id: "appt-\(a.id.uuidString)-remind", at: remindAt, body: L.t("30 分鐘後約咗\(who)喺\(spot)。", "30 分钟后和\(who)约在\(spot)。")))
            }
            let expireAt = a.date.addingTimeInterval(expireAfter)
            if expireAt > now {
                let hour = TemplateAI.hourLabel(AppStore.hk.component(.hour, from: a.date))
                out.append(Item(id: "appt-\(a.id.uuidString)-expire", at: expireAt, body: L.t("同\(who)\(hour)喺\(spot)嘅約過咗時間，收埋咗。", "和\(who)\(hour)在\(spot)的约已过时间，已收起。")))
            }
        }
        return out
    }
}
