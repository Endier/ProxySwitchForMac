//
//  ContentView.swift
//  ProxySwitchSwift
//
//  Created by Cody on 2024/6/11.
//

import AppKit
import KeyboardShortcuts
import SwiftUI
import UserNotifications

struct ContentView: View {
    @Bindable var appState: SystemProxyStatus

    var body: some View {
        TabView {
            ProxySettingView(appState: appState)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }

            PermissionView()
                .tabItem {
                    Label("Permission", systemImage: "hand.raised.square.on.square.fill")
                }
        }
    }
}

struct ProxySettingView: View {
    @Bindable var appState: SystemProxyStatus

    var body: some View {
        Group {
            if appState.isLoading {
                ProgressView("正在检测当前代理状态…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    Section {
                        Toggle(isOn: $appState.totalEnable) {
                            Text("Status")
                        }

                        KeyboardShortcuts.Recorder(
                            "Customize global shortcut", name: .proxySwitch
                        )
                    }
                }
                .formStyle(.grouped)
            }
        }
    }
}

struct PermissionView: View {
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("获取通知权限")

                    Spacer()

                    switch authorizationStatus {
                    case .notDetermined:
                        Button("获取") {
                            requestNotificationPermission()
                            checkStatus()
                        }
                    case .authorized, .provisional, .ephemeral:
                        Text("已授权")
                            .foregroundColor(.green)
                    case .denied:
                        HStack(spacing: 4) {
                            Text("已拒绝")
                                .foregroundColor(.red)
                            Button("打开设置") {
                                if let url = URL(
                                    string:
                                        "x-apple.systempreferences:com.apple.preference.notifications"
                                ) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    @unknown default:
                        Button("获取") {
                            requestNotificationPermission()
                            checkStatus()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task {
            checkStatus()
        }
    }

    private func checkStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                authorizationStatus = status
            }
        }
    }
}

#Preview {
    PermissionView()
}

#Preview {
    ProxySettingView(appState: SystemProxyStatus())
}

#Preview {
    ContentView(appState: SystemProxyStatus())
}
