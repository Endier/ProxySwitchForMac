import Foundation
import KeyboardShortcuts
import UserNotifications

// MARK: - ProxySetting

struct ProxySetting {
    let enable: String
    let server: String
    let port: String
}

// MARK: - NetworkSetupError

enum NetworkSetupError: Error {
    case invalidOutput
}

// MARK: - NetworkSetupService

// 没有 case 的 enum 不能被实例化，所以经常被用来写一些纯工具方法集合
enum NetworkSetupService {
    private static let executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")

    /// 获取所有活跃的网络服务名
    static func getNetworkServiceNames() async throws -> [String] {
        let output = try await run(arguments: ["-listallnetworkservices"])
        return
            output
            .components(separatedBy: .newlines)
            .dropFirst()
            .map { String($0) }
            .filter { !$0.hasPrefix("*") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// 获取指定服务的代理设置（HTTP/HTTPS/SOCKS）
    static func getProxySetting(argument: String, serviceName: String) async throws -> ProxySetting
    {
        let output = try await run(arguments: [argument, serviceName])
        let dict = parseProxyOutput(output)
        return ProxySetting(
            enable: dict["Enabled"] ?? "",
            server: dict["Server"] ?? "",
            port: dict["Port"] ?? ""
        )
    }

    /// 开关指定代理
    static func toggleProxy(argument: String, serviceName: String, enable: Bool) async throws {
        let state = enable ? "on" : "off"
        try await run(arguments: [argument, serviceName, state])
    }

    /// 判断当前代理是否处于开启状态（任一代理开启了即为开启）
    static func isProxyEnabled(serviceNames: [String]) async -> Bool {
        let arguments = ["-getwebproxy", "-getsecurewebproxy", "-getsocksfirewallproxy"]
        for serviceName in serviceNames {
            for argument in arguments {
                if let setting = try? await getProxySetting(
                    argument: argument, serviceName: serviceName),
                    setting.enable == "Yes"
                {
                    return true
                }
            }
        }
        return false
    }

    /// 批量开关代理（HTTP、HTTPS、SOCKS）
    static func setAllProxyStates(serviceNames: [String], enabled: Bool) async {
        let arguments = [
            "-setwebproxystate", "-setsecurewebproxystate",
            "-setsocksfirewallproxystate",
        ]
        for serviceName in serviceNames {
            for argument in arguments {
                try? await toggleProxy(
                    argument: argument, serviceName: serviceName, enable: enabled)
            }
        }
    }

    // MARK: - Private Helpers

    @discardableResult
    private static func run(arguments: [String]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments

            let pipe = Pipe()
            process.standardOutput = pipe

            process.terminationHandler = { _ in
                do {
                    guard let data = try pipe.fileHandleForReading.readToEnd(),
                        let output = String(data: data, encoding: .utf8)
                    else {
                        continuation.resume(throwing: NetworkSetupError.invalidOutput)
                        return
                    }
                    continuation.resume(returning: output)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func parseProxyOutput(_ string: String) -> [String: String] {
        var dict: [String: String] = [:]
        let lines = string.components(separatedBy: .newlines)
        for line in lines {
            let parts = line.components(separatedBy: ": ")
            if parts.count == 2 {
                dict[parts[0]] = parts[1]
            }
        }
        return dict
    }
}

// MARK: - SystemProxyStatus

@MainActor
@Observable
class SystemProxyStatus {
    var totalEnable: Bool = true {
        didSet {
            guard !isRefreshingState else { return }
            toggleTask?.cancel()
            let isEnabled = totalEnable
            toggleTask = Task { @MainActor in
                let serviceNames = await Self.fetchActiveServiceNames()
                await NetworkSetupService.setAllProxyStates(
                    serviceNames: serviceNames, enabled: isEnabled)
                sendNotification(isOn: isEnabled)
            }
        }
    }

    private var toggleTask: Task<Void, Never>?
    /// 初始状态为 `true`，防止 `didSet` 在初始状态加载时触发 toggle
    private var isRefreshingState = true

    nonisolated init() {
        Task { @MainActor in
            let serviceNames = await Self.fetchActiveServiceNames()
            let isEnabled = await NetworkSetupService.isProxyEnabled(serviceNames: serviceNames)
            if !Task.isCancelled {
                self.totalEnable = isEnabled
                self.isRefreshingState = false
            }
        }

        KeyboardShortcuts.onKeyDown(for: .proxySwitch) { [weak self] in
            Task { @MainActor in
                self?.totalEnable.toggle()
            }
        }
    }

    /// 获取活跃的网络服务名，失败时回退到默认值
    private static func fetchActiveServiceNames() async -> [String] {
        guard let names = try? await NetworkSetupService.getNetworkServiceNames(), !names.isEmpty
        else {
            return ["Wi-Fi", "Ethernet"]
        }
        return names
    }
}

// MARK: - KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let proxySwitch = Self("proxySwitch", default: .init(.j, modifiers: .command))
}
