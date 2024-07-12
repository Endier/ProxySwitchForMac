//  ProxySwitchForMacApp.swift
//  ProxySwitchForMac
//
//  Created by Cody on 2024/6/26.
//

import SwiftUI
import SwiftData
import KeyboardShortcuts

@main
struct ProxySwitchForMacApp: App {
    // 实例化后，就可以通过View的参数传入，实现全局变量
    // 一种属性包装器类型，用于订阅可观察对象，并在可观察对象发生变化时使视图失效。
    @ObservedObject var appState = AppState()
    
    var body: some Scene {
        // WindowGroup可以打开多个窗口，适用于多窗口应用
        // Window是单独窗口，适用于单窗口应用
        // Settings是设置窗口
        // MenuBarExtra是菜单栏常驻图标
        
        //        WindowGroup {
        //
        //        }
        //        .windowToolbarStyle(UnifiedWindowToolbarStyle())
        //        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
        
        Window("AppName", id: "mainwindow") {
            if #available(macOS 15.0, *) {
                ContentView(appState: appState)
                    .fixedSize() // 强制内容视图保持固定大小
                    .containerBackground(.regularMaterial, for: .window) // 窗口材质
            } else {
                // Fallback on earlier versions
                ContentView(appState: appState)
                    .frame(minWidth:500, idealWidth: 500, minHeight: 180, idealHeight: 180)
                    .fixedSize() // 强制内容视图保持固定大小
            }
        }
        .windowResizability(.contentSize) // 窗口大小适配View大小
//        .windowStyle(HiddenTitleBarWindowStyle()) // 隐藏窗口TitleBar
//        .defaultWindowPlacement {
//            content, context in
//            var size = content.sizeThatFits(.unspecified)
//            let displayBounds = context.defaultDisplay.visibleRect
////            size = zoomToFit(ideal: size, bounds: displayBounds)
//            return WindowPlacement(size: size)
//        }

//        Settings {
//            SettingsView()
//        }
        
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            if appState.proxySettings.isOn {
                Image("MenuBarIcon")
            } else {
                Image(systemName: "network")
            }
        }
    }
}

// 命名并设置默认快捷键
extension KeyboardShortcuts.Name {
    static let proxySwitch = Self("proxySwitch", default: .init(.j, modifiers: .command))
}

// 创建全局对象和其属性
class AppState: ObservableObject {
    @Published var proxySettings: ProxySettings = getProxySettings(serviceNames: getSystemNetworkServiceNames())
    // 设置自定义全局快捷键逻辑
    init() {
        KeyboardShortcuts.onKeyUp(for: .proxySwitch) { [self] in
            proxySettings.isOn.toggle()
        }
    }
}



