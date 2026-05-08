//
//  ContentView.swift
//  ProxySwitchSwift
//
//  Created by Cody on 2024/6/11.
//

import AppKit
import KeyboardShortcuts
import SwiftUI

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

struct PermissionView: View {
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("获取通知权限")

                    Spacer()

                    Button("获取") {
                        requestNotificationPermission()
                    }
                }
            }
        }
        .formStyle(.grouped)
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
