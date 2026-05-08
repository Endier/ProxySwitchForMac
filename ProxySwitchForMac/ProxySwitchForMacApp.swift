//  ProxySwitchForMacApp.swift
//  ProxySwitchForMac
//
//  Created by Cody on 2024/6/26.
//

import SwiftUI

@main
struct ProxySwitchForMacApp: App {
    @State var appState = SystemProxyStatus()
    @Environment(\.openWindow) private var openWindow

    private func activateMainWindow() {
        if let window = NSApplication.shared.windows.first(where: {
            $0.identifier?.rawValue == "mainwindow"
        }) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            window.level = .floating
        } else {
            openWindow(id: "mainwindow")

            Task {
                try? await Task.sleep(for: .seconds(0.1))
                if let window = NSApplication.shared.windows.first(where: {
                    $0.identifier?.rawValue == "mainwindow"
                }) {
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                    window.orderFrontRegardless()
                    window.level = .floating
                    return  // 找到窗口后退出
                }
            }
        }
    }

    var body: some Scene {
        // WindowGroup可以打开多个窗口，适用于多窗口应用
        // Window是单独窗口，适用于单窗口应用
        // Settings是设置窗口
        // MenuBarExtra是菜单栏常驻图标
        Window("AppName", id: "mainwindow") {
            if #available(macOS 15.0, *) {
                ContentView(appState: appState)
                    .frame(width: 400, height: 120)
                    .containerBackground(.ultraThinMaterial, for: .window)  // 窗口材质
            } else {
                ContentView(appState: appState)
                    .frame(width: 400, height: 120)
            }
        }
        .windowResizability(.contentSize)  // 窗口大小适配View大小

        //        Settings {
        //            SettingsView()
        //        }

        MenuBarExtra {
            Button("打开主窗口") {
                activateMainWindow()
            }

            Divider()

            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        } label: {
            // 菜单栏图标会被系统强制指定颜色，以适配深色模式
            if appState.totalEnable {
                Image(systemName: "network.badge.shield.half.filled")
            } else {
                Image(systemName: "network.slash")
            }
        }
    }
}
