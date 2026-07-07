//  NetworkSetupService.swift
//  ProxySwitchForMac
//
//  通过 networksetup 命令行工具写入（开关）系统代理设置；
//  读取状态已移至 NetworkConfigSource（进程内直读 SCDynamicStore，不再 fork 子进程）。

import Foundation

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

    /// 获取当前活跃的网络服务名；失败或为空时回退到 SCDynamicStore 中的真实服务名，
    /// 再不行才回退到常见英文名（最后兜底层）。
    /// 归位于网络服务层，避免让 UI 状态对象承担基础设施职责。
    static func fetchActiveServiceNames() async -> [String] {
        guard let names = try? await getNetworkServiceNames(), !names.isEmpty else {
            // networksetup 失败：回退到 SCDynamicStore 读到的真实 UserDefinedName，
            // 而非猜测的英文名——中文 macOS 上 "以太网" 等会找不到服务导致开关失效。
            let fallback = NetworkConfigSource.fetchAllServiceNames()
            return fallback.isEmpty ? ["Wi-Fi", "Ethernet"] : fallback
        }
        return names
    }

    /// 开关指定代理
    static func toggleProxy(argument: String, serviceName: String, enable: Bool) async throws {
        let state = enable ? "on" : "off"
        try await run(arguments: [argument, serviceName, state])
    }

    /// 写操作（开关代理）并发上限：限制同时 fork 的 networksetup 进程数。
    static let maxConcurrent: Int = 6

    /// 批量开关代理（HTTP、HTTPS、SOCKS）
    ///
    /// - 关闭（`enabled: false`）：对所有服务、所有代理类型一律尝试关闭（关闭永远安全、无歧义）。
    /// - 开启（`enabled: true`）：仅对**已配置地址**的代理类型启用；未配置（server 为 `"(null)"`/空）的
    ///   代理保持原样，避免去「开启一个没有服务器的代理」。
    ///   `resolvedConfigured` 由调用方从缓存传入以避免重复读取，为空时回退到重新读取。
    ///
    /// 仅当「有需要操作的目标且全部失败」时才抛出错误。并发执行由 AsyncSemaphore 限流。
    static func setAllProxyStates(
        serviceNames: [String],
        enabled: Bool,
        resolvedConfigured: [String: [ProxyType: Bool]]? = nil
    ) async throws {
        // 开启时由调用方从缓存（或 NetworkConfigSource 进程内读取）算出「已配置地址」映射后传入；
        // 关闭时传 nil，表示对所有服务、所有类型一律关闭。
        let resolved: [String: [ProxyType: Bool]]? = resolvedConfigured

        // 组装本次真正要执行的操作：
        //   关闭 = 全部（服务 × 类型）；开启 = 仅已配置地址的类型。
        // 通过 ProxyType 把 get/set 参数按类型绑定，不再依赖两条平行数组的下标对齐。
        let operations: [(serviceName: String, argument: String)] = serviceNames.flatMap { serviceName in
            ProxyType.allCases.compactMap { type in
                if resolved == nil {
                    return (serviceName, type.setArgument)   // 关闭：全部保留
                }
                if resolved?[serviceName]?[type] == true {
                    return (serviceName, type.setArgument)   // 开启：仅已配置地址
                }
                return nil
            }
        }

        // 无可执行操作（如开启时没有任何代理配置地址）：视为成功，无需报错。
        guard !operations.isEmpty else { return }

        // 并发执行：单个失败不影响其余，仅当全部失败时抛错；由信号量限制同时进行的进程数。
        let semaphore = AsyncSemaphore(limit: maxConcurrent)
        let anySucceeded = await withTaskGroup(of: Bool.self) { group in
            for op in operations {
                group.addTask {
                    await semaphore.acquire()
                    defer { await semaphore.release() }
                    return (try? await toggleProxy(
                        argument: op.argument, serviceName: op.serviceName, enable: enabled
                    )) != nil
                }
            }
            var anySucceeded = false
            for await ok in group where ok {
                anySucceeded = true
            }
            return anySucceeded
        }

        if !anySucceeded {
            throw NetworkSetupError.commandFailed(status: -1, message: "所有代理开关操作均失败")
        }
    }

    // MARK: - Private Helpers

    /// 在后台队列读取管道到 EOF。
    /// 注意：本 SDK 的 `FileHandle.readToEnd()` 仅有同步 `throws` 版本（无 async 重载），
    /// 故放到全局后台队列执行，避免阻塞 Foundation 内部线程或主线程
    /// （这正是原先在 terminationHandler 里同步读管道的隐患）。
    private static func readPipe(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let data = (try? handle.readToEnd()) ?? Data()
                continuation.resume(returning: data)
            }
        }
    }

    @discardableResult
    private static func run(arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        let errorPipe = Pipe()
        process.standardError = errorPipe

        // 在 run() 之前就发起异步读取，且 stdout/stderr 并发读：
        // 避免任一管道先写满缓冲导致子进程阻塞，读在后台进行不阻塞任何线程。
        async let outputData = readPipe(pipe.fileHandleForReading)
        async let errorData = readPipe(errorPipe.fileHandleForReading)

        try process.run()

        // 仅等待进程终止通知；terminationHandler 里不再读管道，不阻塞任何线程。
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume() }
        }

        let (output, errorOutput) = await (outputData, errorData)

        guard process.terminationStatus == 0 else {
            let message = String(data: errorOutput, encoding: .utf8) ?? ""
            throw NetworkSetupError.commandFailed(status: process.terminationStatus, message: message)
        }
        return String(data: output, encoding: .utf8) ?? ""
    }
}
