import SwiftUI
import KeyboardShortcuts

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        Toggle(isOn: $appState.isOn){
            Text("代理启用状态")
        }
        .keyboardShortcut("j", modifiers: .command) // TODO 把KeyBoardShortcuts自定义的快捷键展示在这里
        .onChange(of: appState.isOn) {
            let serviceNames: [String] = getSystemNetworkServiceNames()
            let _ = setProxyEnable(serviceNames: serviceNames, bool: appState.isOn)
        }
    }
}
