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
    @State private var selection: Int? = 0
    
    var body: some View {
        //        NavigationSplitView {
        //            List {
        //                NavigationLink("Proxy") {
        //                    DetailView(isOn: $appState.isOn)
        //                }
        //            }
        //        } detail: {
        //            Text("select")
        //        }
        //        .navigationTitle("PorxyTitle")
        DetailView(isOn: $appState.isOn)
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

struct DetailView: View {
    @Binding var isOn: Bool
    
    var body: some View {
        GeometryReader { geometry in
            Form {
                Section {
                    Toggle(isOn: $isOn){
                        Text("代理服务器")
                        Text("启用状态")
                    }
                    .onChange(of: isOn) {
                        let serviceNames: [String] = getSystemNetworkServiceNames()
                        let _ = setProxyEnable(serviceNames: serviceNames, bool: isOn)
                    }
                    
                    KeyboardShortcuts.Recorder("自定义全局快捷键:", name: .proxySwitch)
                }
            }
            .formStyle(.grouped) // Form的这种格式类似于系统设置的选项卡风格
        }
    }
}
