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
                    Label(String(localized: "Settings"), systemImage: "gear")
                }
                .tag(Tab.settings)

            PermissionView()
                .tabItem {
                    Label(String(localized: "Permission"), systemImage: "hand.raised.square.on.square.fill")
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
                ProgressView(String(localized: "正在检测当前代理状态…"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    Section {
                        Toggle(isOn: Binding(
                            get: { appState.isProxyOn },
                            set: { appState.setProxyEnabled($0) }
                        )) {
                            Text(String(localized: "Status"))
                        }

                        KeyboardShortcuts.Recorder(
                            String(localized: "Customize global shortcut"), name: .proxySwitch
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
    @AppStorage(NotificationService.enabledKey) private var notificationEnabled: Bool = true

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(String(localized: "获取通知权限"))

                    Spacer()

                    switch authorizationStatus {
                    case .notDetermined:
                        Button(String(localized: "获取")) {
                            NotificationService.requestPermission {
                                checkStatus()
                            }
                        }
                    case .authorized, .provisional, .ephemeral:
                        Text(String(localized: "已授权"))
                            .foregroundColor(.green)
                    case .denied:
                        HStack(spacing: 4) {
                            Text(String(localized: "已拒绝"))
                                .foregroundColor(.red)
                            Button(String(localized: "打开设置")) {
                                if let url = URL(
                                    string:
                                        "x-apple.systempreferences:com.apple.preference.notifications"
                                ) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    @unknown default:
                        Button(String(localized: "获取")) {
                            NotificationService.requestPermission {
                                checkStatus()
                            }
                        }
                    }
                }

                Toggle(isOn: $notificationEnabled) {
                    Text(String(localized: "Show notification when toggling"))
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
