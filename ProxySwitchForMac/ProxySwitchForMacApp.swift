//  ProxySwitchForMacApp.swift
//  ProxySwitchForMac
//
//  Created by Cody on 2024/6/26.
//

import SwiftData
import SwiftUI

@main
struct ProxySwitchForMacApp: App {
    @State var appState = SystemProxyStatus()

    var body: some Scene {
        // WindowGroup可以打开多个窗口，适用于多窗口应用
        // Window是单独窗口，适用于单窗口应用
        // Settings是设置窗口
        // MenuBarExtra是菜单栏常驻图标
        Window("AppName", id: "mainwindow") {
            if #available(macOS 15.0, *) {
                ContentView(appState: appState)
                    .frame(width: 400, height: 120)
                    .containerBackground(.ultraThinMaterial, for: .window) // 窗口材质
            } else {
                ContentView(appState: appState)
                    .frame(width: 400, height: 120)
            }
        }
        .windowResizability(.contentSize) // 窗口大小适配View大小

//        Settings {
//            SettingsView()
//        }

        MenuBarExtra {
        } label: {
            if appState.totelEnable {
                Image("MenuBarIcon")
            } else {
                Image(systemName: "network")
            }
        }
    }
}
