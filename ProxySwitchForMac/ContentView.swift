//
//  ContentView.swift
//  ProxySwitchSwift
//
//  Created by Cody on 2024/6/11.
//

import SwiftUI
import SwiftData
import AppKit
import Carbon
import KeyboardShortcuts

struct ContentView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        
        HStack {
            Form {
                Section {
//                    TextField("Proxy Server", text: $appState.proxySettings.Server)
//                    //                    .textFieldStyle(RoundedBorderTextFieldStyle()) // 使用带有圆角边框的样式
                    HStack {
                        Text("Proxy server")
                        
                        Spacer()
                        
                        Button(appState.proxySettings.Server) {
                            copyToClipboard(text: appState.proxySettings.Server)
                        }
                        .help("Click to copy")

                        Text(":")
                            .fontWeight(.bold)
                        
                        Button(appState.proxySettings.Port) {
                            copyToClipboard(text: appState.proxySettings.Port)
                        }
                        .help("Click to copy")
                    }
                    
                    Toggle(isOn: $appState.proxySettings.isOn){
                        Text("Status")
                    }
                    .onChange(of: appState.proxySettings.isOn) {
                        let serviceNames: [String] = getSystemNetworkServiceNames()
                        let _ = setProxyEnable(serviceNames: serviceNames, bool: appState.proxySettings.isOn)
                    }
                    
                    KeyboardShortcuts.Recorder("Customize global shortcut", name: .proxySwitch)
                }
            }
            .formStyle(.grouped) // Form的这种格式类似于系统设置的选项卡风格
        }
    }
}

//Int：这意味着每个枚举成员都有一个与之关联的整数值，这个值默认从0开始。
//Hashable：这意味着枚举类型可以被唯一地标识和比较。
//CaseIterable：这意味着枚举类型可以提供一个包含所有成员的集合，可以用于迭代。
//Identifiable：这意味着枚举类型有一个可以唯一标识其成员的属性id。
//Codable：这意味着枚举类型可以被编码和解码，例如转换为JSON。
//enum test: Int, Hashable, CaseIterable, Identifiable, Codable {
//
//}

func copyToClipboard(text: String) {
    let pasteBoard = NSPasteboard.general
    pasteBoard.clearContents()
    pasteBoard.setString(text, forType: .string)
}
