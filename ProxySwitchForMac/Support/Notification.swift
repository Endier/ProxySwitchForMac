import Foundation
import UserNotifications

/// 通知开关的 UserDefaults key
private let notificationEnabledKey = "notificationEnabled"

/// 检查用户是否开启了通知
func isNotificationEnabled() -> Bool {
    UserDefaults.standard.object(forKey: notificationEnabledKey) as? Bool ?? true
}

/// 设置通知开关
func setNotificationEnabled(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: notificationEnabledKey)
}

// 以下三个方法因为调用了 UNUserNotificationCenter（非 Sendable）和 UserDefaults，所以只能在 @MainActor 里调用，不然会有 data race
@MainActor
func requestNotificationPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
        _, error in
        if let error {
            print(error.localizedDescription)
        }
    }
}

@MainActor
func sendNotification(isOn: Bool) {
    guard isNotificationEnabled() else { return }

    let content = UNMutableNotificationContent()
    content.title = String(localized: "AppName")
    if isOn {
        content.body = String(localized: "Your network proxy has been turned ON.")
    } else {
        content.body = String(localized: "Your network proxy has been turned OFF.")
    }
    content.sound = UNNotificationSound.default

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(
        identifier: "proxyStatusChanged", content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request) { error in
        if let error = error {
            print("Failed to send notification: \(error)")
        }
    }
}

@MainActor
func sendErrorNotification(error: Error) {
    guard isNotificationEnabled() else { return }

    let content = UNMutableNotificationContent()
    content.title = String(localized: "AppName")
    content.body = String(localized: "Failed to toggle proxy: \(error.localizedDescription)")
    content.sound = UNNotificationSound.default

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(
        identifier: "proxyToggleError", content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request) { error in
        if let error = error {
            print("Failed to send error notification: \(error)")
        }
    }
}
