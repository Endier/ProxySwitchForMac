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
    @State private var selectedTab: Tab = .settings

    enum Tab: String, CaseIterable {
        case settings
        case permission
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            ProxySettingView(appState: appState)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(Tab.settings)

            PermissionView()
                .tabItem {
                    Label("Permission", systemImage: "hand.raised.square.on.square.fill")
                }
                .tag(Tab.permission)
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
                        Toggle(isOn: Binding(
                            get: { appState.totalEnable },
                            set: { appState.setProxyEnabled($0) }
                        )) {
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
    @AppStorage("notificationEnabled") private var notificationEnabled: Bool = true

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
                
                Toggle(isOn: $notificationEnabled) {
                    Text("Show notification when toggling")
                }
                .onChange(of: notificationEnabled) { _, newValue in
                    setNotificationEnabled(newValue)
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
    ProxySettingView(appState: SystemProxyStatus(previewEnabled: true))
}

#Preview {
    ContentView(appState: SystemProxyStatus(previewEnabled: true))
}
