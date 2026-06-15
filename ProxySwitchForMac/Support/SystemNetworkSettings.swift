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
    case commandFailed(status: Int32, message: String)
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

    /// 检查当前代理是否「全开」——所有活跃服务的 HTTP、HTTPS、SOCKS 都必须为 Yes
    ///
    /// 跳过没有配置代理的服务或代理类型（server 为空或命令失败），
    /// 只检查实际存在配置的代理是否全部开启。
    static func isProxyEnabled(serviceNames: [String]) async -> Bool {
        let arguments = ["-getwebproxy", "-getsecurewebproxy", "-getsocksfirewallproxy"]
        var anyEnabled = false
        for serviceName in serviceNames {
            for argument in arguments {
                if let setting = try? await getProxySetting(
                    argument: argument, serviceName: serviceName
                ) {
                    // 有代理配置：检查是否开启
                    if setting.enable == "Yes" {
                        anyEnabled = true
                    } else if !setting.server.isEmpty {
                        // 已配置但未开启 → 不算全开
                        return false
                    }
                }
                // setting 为 nil 或无 server：该服务未使用此代理类型，跳过
            }
        }
        return anyEnabled
    }

    /// 批量开关代理（HTTP、HTTPS、SOCKS）
    ///
    /// 开启时（`enabled: true`）：跳过个别失败的代理类型（如未配置 SOCKS），
    /// 仅当全部失败时才抛出错误。关闭时一律尝试，全部失败才抛出错误。
    static func setAllProxyStates(serviceNames: [String], enabled: Bool) async throws {
        let arguments = [
            "-setwebproxystate", "-setsecurewebproxystate",
            "-setsocksfirewallproxystate",
        ]
        var failures = 0
        for serviceName in serviceNames {
            for argument in arguments {
                do {
                    try await toggleProxy(
                        argument: argument, serviceName: serviceName, enable: enabled
                    )
                } catch {
                    failures += 1
                }
            }
        }
        let total = serviceNames.count * arguments.count
        if failures == total {
            throw NetworkSetupError.commandFailed(
                status: -1, message: "所有代理开关操作均失败"
            )
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
            let errorPipe = Pipe()
            process.standardError = errorPipe

            process.terminationHandler = { _ in
                let errorMessage =
                    (try? errorPipe.fileHandleForReading.readToEnd())
                        .flatMap { String(data: $0, encoding: .utf8) } ?? ""

                guard process.terminationStatus == 0 else {
                    continuation.resume(
                        throwing: NetworkSetupError.commandFailed(
                            status: process.terminationStatus,
                            message: errorMessage
                        ))
                    return
                }

                do {
                    let data: Data
                    if let readData = try pipe.fileHandleForReading.readToEnd() {
                        data = readData
                    } else {
                        // Pipe 在写端关闭后且无数据时返回 nil，对于无输出的命令是正常情况
                        data = Data()
                    }
                    let output = String(data: data, encoding: .utf8) ?? ""
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
    /// 当前代理开启状态
    var totalEnable: Bool = true {
        didSet {
            guard !isRefreshingState else { return }
            let isEnabled = totalEnable
            // 排队等上一个任务自然完成，避免取消导致的续体 race
            toggleTask = Task { [previousTask = toggleTask] in
                _ = await previousTask?.value
                let serviceNames = await Self.fetchActiveServiceNames()
                do {
                    try await NetworkSetupService.setAllProxyStates(
                        serviceNames: serviceNames, enabled: isEnabled
                    )
                    sendNotification(isOn: isEnabled)
                } catch {
                    isRefreshingState = true
                    totalEnable = !isEnabled
                    isRefreshingState = false
                    sendErrorNotification(error: error)
                }
            }
        }
    }

    /// 初始状态加载中，UI 应显示加载动画而非实际状态
    private(set) var isLoading = true

    private var toggleTask: Task<Void, Never>?
    /// 初始状态为 `true`，防止 `didSet` 在初始状态加载时触发 toggle
    private var isRefreshingState = true

    nonisolated init() {
        Task { @MainActor in
            let serviceNames = await Self.fetchActiveServiceNames()
            let isEnabled = await NetworkSetupService.isProxyEnabled(serviceNames: serviceNames)
            if !Task.isCancelled {
                if !isEnabled {
                    // 判定为关闭时，确保所有代理都关掉（避免残留个别开关开着）
                    try? await NetworkSetupService.setAllProxyStates(
                        serviceNames: serviceNames, enabled: false
                    )
                }
                self.totalEnable = isEnabled
                self.isRefreshingState = false
                self.isLoading = false

                KeyboardShortcuts.onKeyDown(for: .proxySwitch) {
                    self.totalEnable.toggle()
                }
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
    static let proxySwitch = Self("proxySwitch", initial: .init(.j, modifiers: .command))
}
