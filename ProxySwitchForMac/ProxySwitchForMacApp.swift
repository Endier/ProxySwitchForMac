//  ProxySwitchForMacApp.swift
//  ProxySwitchForMac
//
//  Created by Cody on 2024/6/26.
//

import KeyboardShortcuts
import SwiftUI

@main
struct ProxySwitchForMacApp: App {
    @State var appState = SystemProxyStatus(onToggleResult: { enabled, error in
        if let error {
            if let toggleError = error as? ProxyToggleError {
                // 预期拦截（如主服务未配置代理地址）：用「提示」而非「失败」措辞
                NotificationService.sendInfo(toggleError.localizedDescription)
            } else {
                NotificationService.sendError(error)
            }
        } else {
            NotificationService.send(isOn: enabled)
        }
    })
    @Environment(\.openWindow) private var openWindow

    /// 快捷键「输入」关注点归位于 App 层：全局快捷键只负责把事件转发给状态对象，
    /// 不再由 SystemProxyStatus 自己注册；状态对象通过 onToggleResult 回调把开关结果交出去，不直接依赖通知 UI。
    init() {
        KeyboardShortcuts.onKeyDown(for: .proxySwitch) { [appState] in
            Task { @MainActor in
                appState.setProxyEnabled(!appState.isProxyOn)
            }
        }
    }

    private func activateMainWindow() {
        if let window = findMainWindow() {
            bringWindowToFront(window)
            return
        }

        // 窗口还不存在，openWindow 创建后用 NotificationCenter 异步序列等待其成为 key 窗口，
        // 再将其提到前台。用 Swift 并发替代 Combine，无需 CancellableBag 持有订阅。
        openWindow(id: "mainwindow")

        Task { @MainActor in
            for await notification in NotificationCenter.default
                .notifications(named: NSWindow.didBecomeKeyNotification)
            {
                guard let window = notification.object as? NSWindow,
                      window.identifier?.rawValue == "mainwindow"
                else { continue }
                bringWindowToFront(window)
                break
            }
        }
    }

    private func findMainWindow() -> NSWindow? {
        NSApplication.shared.windows.first { $0.identifier?.rawValue == "mainwindow" }
    }

    private func bringWindowToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// 主窗口内容。抽出以避免在 body 里因可用性分支重复构造 ContentView。
    @MainActor
    @ViewBuilder
    private var mainWindowContent: some View {
        let content = ContentView(appState: appState)
            .frame(width: 400, height: 120)
        if #available(macOS 15.0, *) {
            content.containerBackground(.ultraThinMaterial, for: .window)
        } else {
            content
        }
    }

    var body: some Scene {
        Window("AppName", id: "mainwindow") {
            mainWindowContent
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            Button(String(localized: "打开主窗口")) {
                activateMainWindow()
            }

            Divider()

            Button(String(localized: "退出")) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        } label: {
            if appState.isLoading {
                Image(systemName: "network")
            } else if appState.isProxyOn {
                Image(systemName: "network.badge.shield.half.filled")
            } else {
                Image(systemName: "network.slash")
            }
        }
    }
}
