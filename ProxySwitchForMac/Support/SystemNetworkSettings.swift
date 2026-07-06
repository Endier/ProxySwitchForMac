import Foundation
import KeyboardShortcuts
import UserNotifications

// MARK: - ProxySetting

struct ProxySetting {
    let enable: Bool
    let server: String
    let port: String

    /// 是否已真正启用（排除 networksetup 对未配置代理返回的 "(null)" 误判）
    var isActive: Bool {
        enable && !server.isEmpty && server != "(null)"
    }

    /// 是否已配置地址（无论开关是否打开），用于决定开启时是否启用该代理
    var isConfigured: Bool {
        !server.isEmpty && server != "(null)"
    }
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
            enable: dict["Enabled"] == "Yes",
            server: dict["Server"] ?? "",
            port: dict["Port"] ?? ""
        )
    }

    /// 开关指定代理
    static func toggleProxy(argument: String, serviceName: String, enable: Bool) async throws {
        let state = enable ? "on" : "off"
        try await run(arguments: [argument, serviceName, state])
    }

    /// 判断当前代理是否「生效」：任一活跃服务上任一代理类型已启用即视为开。
    ///
    /// 不再要求 HTTP/HTTPS/SOCKS 全部开启（现实里往往只配了其中一两个），
    /// 也不再因未配置代理返回的 `"(null)"` 而误判为「已配置但关闭」。
    static func isProxyEnabled(serviceNames: [String]) async -> Bool {
        let arguments = ["-getwebproxy", "-getsecurewebproxy", "-getsocksfirewallproxy"]
        for serviceName in serviceNames {
            for argument in arguments {
                if let setting = try? await getProxySetting(
                    argument: argument, serviceName: serviceName
                ), setting.isActive {
                    return true
                }
            }
        }
        return false
    }

    /// 批量开关代理（HTTP、HTTPS、SOCKS）
    ///
    /// - 关闭（`enabled: false`）：对所有服务、所有代理类型一律尝试关闭（关闭永远安全、无歧义）。
    /// - 开启（`enabled: true`）：仅对**已配置地址**的代理类型启用；未配置（server 为 `"(null)"`/空）的
    ///   代理保持原样，避免去「开启一个没有服务器的代理」。
    ///
    /// 仅当「有需要操作的目标且全部失败」时才抛出错误。
    static func setAllProxyStates(serviceNames: [String], enabled: Bool) async throws {
        let getArgs = ["-getwebproxy", "-getsecurewebproxy", "-getsocksfirewallproxy"]
        let setArgs = ["-setwebproxystate", "-setsecurewebproxystate", "-setsocksfirewallproxystate"]

        try await withThrowingTaskGroup(of: Bool.self) { group in
            for serviceName in serviceNames {
                for i in getArgs.indices {
                    let getArg = getArgs[i]
                    let setArg = setArgs[i]
                    group.addTask {
                        if !enabled {
                            // 关闭：对所有服务、所有代理类型一律尝试
                            return (try? await toggleProxy(
                                argument: setArg, serviceName: serviceName, enable: false
                            )) != nil
                        }
                        // 开启：仅启用已配置地址的代理；未配置则跳过（视为成功，避免误报失败）
                        guard let setting = try? await getProxySetting(
                            argument: getArg, serviceName: serviceName
                        ), setting.isConfigured else {
                            return true
                        }
                        return (try? await toggleProxy(
                            argument: setArg, serviceName: serviceName, enable: true
                        )) != nil
                    }
                }
            }

            var attempted = 0
            var failures = 0
            for try await succeeded in group {
                attempted += 1
                if !succeeded { failures += 1 }
            }
            if attempted > 0, failures == attempted {
                throw NetworkSetupError.commandFailed(
                    status: -1, message: "所有代理开关操作均失败"
                )
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
    /// 当前代理是否生效（任一代理已启用即视为开）
    var isProxyOn: Bool = true

    /// 初始状态加载中，UI 应显示加载动画而非实际状态
    private(set) var isLoading = true

    private var toggleTask: Task<Void, Never>?

    init() {
        KeyboardShortcuts.onKeyDown(for: .proxySwitch) {
            Task { @MainActor in
                self.setProxyEnabled(!self.isProxyOn)
            }
        }

        performInitialLoad()
    }

    /// SwiftUI Preview 专用，跳过 networksetup 调用
    init(previewEnabled: Bool) {
        isProxyOn = previewEnabled
        isLoading = false
    }

    private func performInitialLoad() {
        Task {
            let serviceNames = await Self.fetchActiveServiceNames()
            // 仅读取实际状态用于初始化显示，绝不主动改写系统代理配置
            let isEnabled = await NetworkSetupService.isProxyEnabled(serviceNames: serviceNames)
            self.isProxyOn = isEnabled
            self.isLoading = false
        }
    }

    /// 开关代理，由 UI Toggle 和快捷键统一调用
    func setProxyEnabled(_ enabled: Bool) {
        guard isProxyOn != enabled else { return }
        isProxyOn = enabled

        toggleTask = Task { [previousTask = toggleTask] in
            _ = await previousTask?.value
            let serviceNames = await Self.fetchActiveServiceNames()
            do {
                try await NetworkSetupService.setAllProxyStates(
                    serviceNames: serviceNames, enabled: enabled
                )
                sendNotification(isOn: enabled)
            } catch {
                self.isProxyOn = !enabled
                sendErrorNotification(error: error)
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
