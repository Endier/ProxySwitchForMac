import Foundation
import UserNotifications

/// 桥接非 Sendable 闭包到 @Sendable 上下文用的盒子。
/// requestAuthorization 的回调是 @Sendable，无法直接捕获普通 `() -> Void`，
/// 这里显式断言其可跨并发域传递（UI 回调本就在主线程使用，安全）。
private struct CallbackBox: @unchecked Sendable {
    let call: () -> Void
}

/// 通知相关能力的命名空间，与 NetworkSetupService 同风格（不可实例化的实用类型集合）。
enum NotificationService {
    /// 通知开关的 UserDefaults key（与 ContentView 的 @AppStorage 共用，避免硬编码重复）
    static let enabledKey = "notificationEnabled"

    /// 检查用户是否开启了通知（与 ContentView 的 @AppStorage 读写同一份 UserDefaults，无需额外写入函数）
    static func isEnabled() -> Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// 请求通知授权。调用了 UNUserNotificationCenter（非 Sendable），
    /// 只能在 @MainActor 里调用，避免 data race。
    @MainActor
    static func requestPermission(completion: @escaping () -> Void = {}) {
        // requestAuthorization 的回调是 @Sendable，无法直接捕获非 Sendable 的 completion；
        // 用 CallbackBox 桥接，保持调用方签名不变且消除警告。
        let box = CallbackBox(call: completion)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) {
            _, error in
            if let error {
                print(error.localizedDescription)
            }
            // 授权结果在回调返回后才真正落地，必须在回调内再查询设置状态，
            // 避免外面立即 checkStatus() 读到仍是 notDetermined 的旧值。
            box.call()
        }
    }

    /// 统一发送一条通知：固定标题(AppName)、即时投递(trigger 为 nil)；
    /// 固定 identifier 使连续同类型通知替换旧的、天然去重；仅在用户开启通知时发送。
    /// 各公开方法只负责组装 body 文本与 identifier。
    private static func post(body: String, identifier: String) {
        guard isEnabled() else { return }

        let content = UNMutableNotificationContent()
        content.title = String(localized: "AppName")
        content.body = body
        content.sound = UNNotificationSound.default

        let request = UNNotificationRequest(
            identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to send notification: \(error)")
            }
        }
    }

    @MainActor
    static func send(isOn: Bool) {
        let body = isOn
            ? String(localized: "Your network proxy has been turned ON.")
            : String(localized: "Your network proxy has been turned OFF.")
        post(body: body, identifier: "proxyStatusChanged")
    }

    @MainActor
    static func sendError(_ error: Error) {
        post(
            body: String(localized: "Failed to toggle proxy: \(error.localizedDescription)"),
            identifier: "proxyToggleError"
        )
    }

    /// 预期的「提示」类通知（非失败）：如主服务未配置代理地址时拒绝开启，给用户信息而非报错。
    @MainActor
    static func sendInfo(_ message: String) {
        post(body: message, identifier: "proxyInfo")
    }
}
