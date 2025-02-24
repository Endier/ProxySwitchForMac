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

// Int：这意味着每个枚举成员都有一个与之关联的整数值，这个值默认从0开始。
// Hashable：这意味着枚举类型可以被唯一地标识和比较。
// CaseIterable：这意味着枚举类型可以提供一个包含所有成员的集合，可以用于迭代。
// Identifiable：这意味着枚举类型有一个可以唯一标识其成员的属性id。
// Codable：这意味着枚举类型可以被编码和解码，例如转换为JSON。
// enum test: Int, Hashable, CaseIterable, Identifiable, Codable {
//
// }

struct ProxySettingView: View {
    @Bindable var appState: SystemProxyStatus

    var body: some View {
        Form {
            Section {
//                    TextField(
//                        "Proxy Server", text: $appState.proxySettings.Server
//                    )
//                    .textFieldStyle(RoundedBorderTextFieldStyle() // 使用带有圆角边框的样式

                Toggle(isOn: $appState.totelEnable) {
                    Text("Status")
                }

                KeyboardShortcuts.Recorder(
                    "Customize global shortcut", name: .proxySwitch)
            }
        }
        .formStyle(.grouped) // Form的这种格式类似于系统设置的选项卡风格
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
//    ContentView(appState: SystemProxyStatus())
    PermissionView()
}
