//
//  Notification.swift
//  ProxySwitchForMac
//
//  Created by Cody on 2024/7/24.
//

import Foundation
import UserNotifications

func requestNotificationPermission(center: UNUserNotificationCenter) async -> UNUserNotificationCenter {
    do {
        try await center.requestAuthorization(options: [.alert, .sound])
    } catch {
        print("No Notification Permission")
    }    
    return center
}

func sentNotifications(center: UNUserNotificationCenter, isOn: Bool) async {
    let content = UNMutableNotificationContent()
    content.title = "Proxy Switch"
    if isOn {
        content.body =  NSLocalizedString("Your network proxy has been turned ON.", comment: "")
    } else {
        content.body = NSLocalizedString("Your network proxy has been turned OFF.", comment: "")
    }
    
    content.sound = UNNotificationSound.default
    
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    
    let request = UNNotificationRequest(identifier: "proxyStatusChanged", content: content, trigger: trigger)
    
    do {
        try await center.add(request)
    } catch {
        print("通知发送失败")
    }
    
}




