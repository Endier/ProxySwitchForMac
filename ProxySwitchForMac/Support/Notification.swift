import Foundation
import UserNotifications

func requestNotificationPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
        _, error in
        if let error {
            print(error.localizedDescription)
        }
    }
}

func sendNotification(isOn: Bool) {
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

func sendErrorNotification(error: Error) {
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
