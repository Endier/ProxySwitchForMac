//
//  ContentView.swift
//  ProxySwitchSwift
//
//  Created by Cody on 2024/6/11.
//

import AppKit
import Carbon
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
                Toggle(isOn: $appState.totelEnable) {
                    Text("Status")
                }

                KeyboardShortcuts.Recorder(
                    "Customize global shortcut", name: .proxySwitch)
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

//                        Button(appState.proxySettingList[0].Server) {
//                            copyToClipboard(text: appState.proxySettingList[0].Server)
//                        }
//                        .help("Click to copy")

//                        Text(":")
//                            .fontWeight(.bold)

//                        Button(appState.proxySettingList[0].Port) {
//                            copyToClipboard(text: appState.proxySettingList[0].Port)
//                        }
//                        .help("Click to copy")

                    Button("获取") {
                        requestNotificationPermission()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

//func copyToClipboard(text: String) {
//    let pasteBoard = NSPasteboard.general
//    pasteBoard.clearContents()
//    pasteBoard.setString(text, forType: .string)
//}

#Preview {
    PermissionView()
}
