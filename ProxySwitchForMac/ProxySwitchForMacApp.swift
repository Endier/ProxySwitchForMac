//  ProxySwitchForMacApp.swift
//  ProxySwitchForMac
//
//  Created by Cody on 2024/6/26.
//

import SwiftData
import SwiftUI

@main
struct ProxySwitchForMacApp: App {
    // 实例化后，就可以通过View的参数传入，实现全局变量
    // 一种属性包装器类型，用于订阅可观察对象，并在可观察对象发生变化时使视图失效。
    @State var appState = SystemProxyStatus()
    

//    var sharedModelContainer: ModelContainer = {
//        let schema = Schema([ProxySettings.self])
//
//        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
//
//        do {
//            return try ModelContainer(for: schema, configurations: [modelConfiguration])
//        } catch {
//            fatalError("Could not create ModelContainer: \(error)")
//        }
//    }()

//    private let updaterController: SPUStandardUpdaterController

//    init() {
//        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
//    }

    var body: some Scene {
        // WindowGroup可以打开多个窗口，适用于多窗口应用
        // Window是单独窗口，适用于单窗口应用
        // Settings是设置窗口
        // MenuBarExtra是菜单栏常驻图标

        //        WindowGroup {
        //
        //        }
        //        .windowToolbarStyle(UnifiedWindowToolbarStyle())
        //        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))

        Window("AppName", id: "mainwindow") {
            if #available(macOS 15.0, *) {
                ContentView(appState: appState)
                    .fixedSize() // 强制内容视图保持固定大小
                    .containerBackground(.thinMaterial, for: .window) // 窗口材质
            } else {
                // Fallback on earlier versions
                ContentView(appState: appState)
                    .fixedSize() // 强制内容视图保持固定大小
            }
        }
        .windowResizability(.contentSize) // 窗口大小适配View大小
//        .windowStyle(HiddenTitleBarWindowStyle()) // 隐藏窗口TitleBar
//        .defaultWindowPlacement {
//            content, context in
//            var size = content.sizeThatFits(.unspecified)
//            let displayBounds = context.defaultDisplay.visibleRect
//            size = zoomToFit(ideal: size, bounds: displayBounds)
//            return WindowPlacement(size: size)
//        .commands() {
//            CommandGroup(after: .appInfo) {
//                CheckForUpdateView(updater: updaterController.updater)
//            }
//        }
//        .modelContainer(sharedModelContainer)

//        Settings {
//            SettingsView()
//        }

        MenuBarExtra {
            
        } label: {
            if appState.totelEnable {
                Image("MenuBarIcon")
            } else {
                Image(systemName: "network")
            }
        }
//        .modelContainer(sharedModelContainer)
    }
}


// 创建全局对象和其属性


// This view model class publishes when new updates can be checked by the user
// final class CheckForUpdatesViewModel: ObservableObject {
//    @Published var canCheckForUpdates = false
//
//    init(updater: SPUUpdater) {
//        updater.publisher(for: \.canCheckForUpdates)
//            .assign(to: &$canCheckForUpdates)
//    }
// }

// This is the view for the Check for Updates menu item
// Note this intermediate view is necessary for the disabled state on the menu item to work properly before Monterey.
// See https://stackoverflow.com/questions/68553092/menu-not-updating-swiftui-bug for more info
// struct CheckForUpdateView: View {
//    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
//    private let updater: SPUUpdater
//
//    init(updater: SPUUpdater) {
//        self.updater = updater
//
//        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
//    }
//
//    var body: some View {
//        Button("Check for Updates...", action: updater.checkForUpdates)
//            .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
//    }
// }
