import SwiftUI
import KeyboardShortcuts

struct MenuBarView: View {
    @ObservedObject var appState: AppState
    
    var body: some View {
        Toggle(isOn: $appState.proxySettings.isOn){
            Text("Status")
        }
        .keyboardShortcut("j", modifiers: .command) // TODO 把KeyBoardShortcuts自定义的快捷键展示在这里
        .onChange(of: appState.proxySettings.Enabled) {
            let serviceNames: [String] = getSystemNetworkServiceNames()
            let _ = setProxyEnable(serviceNames: serviceNames, bool: appState.proxySettings.isOn)
        }
    }
}
