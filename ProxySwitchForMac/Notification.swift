//
//  Notification.swift
//  ProxySwitchForMac
//
//  Created by Cody on 2024/7/24.
//

import Foundation
import UserNotifications

public func requestNotificationPermission(center: UNUserNotificationCenter) async -> UNUserNotificationCenter {
    do {
        try await center.requestAuthorization(options: [.alert, .sound])
    } catch {
        print("No Notification Permission")
    }    
    return center
}

public func sentNotifications(center: UNUserNotificationCenter, proxySettings: ProxySettings) async {
    
    let content = UNMutableNotificationContent()
    content.title = "Proxy Switch"
    if proxySettings.isOn {
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




