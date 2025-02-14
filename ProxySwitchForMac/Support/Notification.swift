//
//  Notification.swift
//  ProxySwitchForMac
//
//  Created by Cody on 2024/7/24.
//

import Foundation
import UserNotifications

func requestNotificationPermission() {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
        success, error in
        if success {
        } else if let error {
            print(error.localizedDescription)
        }
    }
}

func sentNotifications(isOn: Bool) {
    let content = UNMutableNotificationContent()

    content.title = "Proxy Switch"
    if isOn {
        content.body = NSLocalizedString("Your network proxy has been turned ON.", comment: "")
    } else {
        content.body = NSLocalizedString("Your network proxy has been turned OFF.", comment: "")
    }
    content.sound = UNNotificationSound.default

    // show this notification 1 second from now
    // time interval must be greater than 0
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

    let request = UNNotificationRequest(identifier: "proxyStatusChanged", content: content, trigger: trigger)

    UNUserNotificationCenter.current().add(request)
}
