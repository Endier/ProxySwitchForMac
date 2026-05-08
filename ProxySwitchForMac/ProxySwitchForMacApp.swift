//  ProxySwitchForMacApp.swift
//  ProxySwitchForMac
//
//  Created by Cody on 2024/6/26.
//

import Combine
import SwiftUI

/// 用于在 struct 中持有 Cancellable 集合（避免 mutating 问题）
final class CancellableBag {
    var cancellables = Set<AnyCancellable>()
}

@main
struct ProxySwitchForMacApp: App {
    @State var appState = SystemProxyStatus()
    @Environment(\.openWindow) private var openWindow
    private let cancellableBag = CancellableBag()

    private func activateMainWindow() {
        if let window = findMainWindow() {
            bringWindowToFront(window)
            return
        }

        // 窗口还不存在，openWindow 创建后监听就绪通知，不靠固定延时
        cancellableBag.cancellables.removeAll()
        NotificationCenter.default
            .publisher(for: NSWindow.didBecomeKeyNotification)
            .compactMap { $0.object as? NSWindow }
            .first { $0.identifier?.rawValue == "mainwindow" }
            .timeout(.seconds(5), scheduler: DispatchQueue.main)
            .sink(
                receiveCompletion: { _ in },
                receiveValue: { bringWindowToFront($0) }
            )
            .store(in: &cancellableBag.cancellables)

        openWindow(id: "mainwindow")
    }

    private func findMainWindow() -> NSWindow? {
        NSApplication.shared.windows.first { $0.identifier?.rawValue == "mainwindow" }
    }

    private func bringWindowToFront(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.level = .floating
    }

    var body: some Scene {
        Window("AppName", id: "mainwindow") {
            if #available(macOS 15.0, *) {
                ContentView(appState: appState)
                    .frame(width: 400, height: 120)
                    .containerBackground(.ultraThinMaterial, for: .window)
            } else {
                ContentView(appState: appState)
                    .frame(width: 400, height: 120)
            }
        }
        .windowResizability(.contentSize)

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
            if appState.totalEnable {
                Image(systemName: "network.badge.shield.half.filled")
            } else {
                Image(systemName: "network.slash")
            }
        }
    }
}
