//  NetworkSetupService.swift
//  ProxySwitchForMac
//
//  通过 networksetup 命令行工具写入（开关）系统代理设置；
//  读取状态已移至 NetworkConfigSource（进程内直读 SCDynamicStore，不再 fork 子进程）。

import Foundation

// 没有 case 的 enum 不能被实例化，所以经常被用来写一些纯工具方法集合
enum NetworkSetupService {
    private static let executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")

    /// 开关指定代理
    static func toggleProxy(argument: String, serviceName: String, enable: Bool) async throws {
        let state = enable ? "on" : "off"
        try await run(arguments: [argument, serviceName, state])
    }

    /// 各代理类型的开关结果汇总，用于区分「全成功 / 部分失败 / 全失败」。
    struct ProxyStatesResult {
        /// 成功执行的代理类型。
        let succeeded: Set<ProxyType>
        /// 失败的代理类型及其真实错误文案（networksetup 的 stderr），仅用于日志与提示。
        let failed: [ProxyType: String]

        /// 全部失败（无任何类型成功），调用方应视为失败并回滚。
        var isAllFailed: Bool { succeeded.isEmpty }
        /// 部分失败（既有成功也有失败），调用方可据此补一条提示通知。
        var isPartialFailure: Bool { !succeeded.isEmpty && !failed.isEmpty }
    }

    /// 对单个网络服务开关代理（HTTP、HTTPS、SOCKS）。
    ///
    /// - 关闭（`enabled: false`）：对该服务所有代理类型一律关闭（关闭永远安全、无歧义）。
    /// - 开启（`enabled: true`）：仅对**已配置地址**的代理类型启用；未配置地址的保持原样，
    ///   避免去「开启一个没有服务器的代理」。`resolvedConfigured` 标记哪些类型已配置地址，
    ///   由调用方（开关前直读）传入；为空（理论不会发生）时无任何操作，视为成功。
    ///
    /// 各类型并发执行，单个失败不影响其余；返回每种类型的成败明细：
    /// 仅当**全部失败**时抛错（触发上层回滚），部分失败视为成功但由调用方补提示。
    static func setProxyStates(
        serviceName: String,
        enabled: Bool,
        resolvedConfigured: [ProxyType: Bool]? = nil
    ) async throws -> ProxyStatesResult {
        // 关闭：所有类型；开启：仅已配置地址的类型。
        let targets: [(type: ProxyType, argument: String)] = ProxyType.allCases.compactMap { type in
            if enabled {
                return resolvedConfigured?[type] == true ? (type, type.setArgument) : nil
            }
            return (type, type.setArgument)
        }

        // 无可执行操作（如开启时没有任何代理配置地址）：视为成功，无需报错。
        guard !targets.isEmpty else {
            return ProxyStatesResult(succeeded: [], failed: [:])
        }

        // 并发执行各类型，记录每个类型的成败与真实错误（单个失败不影响其余）。
        // 错误只保留文案（String，Sendable），不在任务组间跨发 Error 协议值。
        let (succeeded, failed) = await withTaskGroup(
            of: (type: ProxyType, ok: Bool, message: String?).self
        ) { group in
            for (type, argument) in targets {
                group.addTask {
                    do {
                        try await toggleProxy(argument: argument, serviceName: serviceName, enable: enabled)
                        return (type, true, nil)
                    } catch {
                        let message = (error as? NetworkSetupError)?.errorDescription
                            ?? error.localizedDescription
                        return (type, false, message)
                    }
                }
            }
            var succeeded: Set<ProxyType> = []
            var failed: [ProxyType: String] = [:]
            for await (type, ok, message) in group {
                if ok {
                    succeeded.insert(type)
                } else if let message {
                    failed[type] = message
                }
            }
            return (succeeded, failed)
        }

        let result = ProxyStatesResult(succeeded: succeeded, failed: failed)

        // 记录失败类型的真实错误，便于排查（部分失败时用户不会收到报错通知）。
        let action = enabled ? "开启" : "关闭"
        for (type, message) in result.failed {
            print("代理开关部分失败 [\(serviceName)] \(type.displayName) \(action)失败：\(message)")
        }

        // 仅全部失败时抛错，触发上层回滚；部分失败视为成功（由调用方补提示）。
        if result.isAllFailed {
            let detail = result.failed.values.joined(separator: "；")
            throw NetworkSetupError.commandFailed(
                status: -1,
                message: "所有代理开关操作均失败" + (detail.isEmpty ? "" : "：\(detail)")
            )
        }
        return result
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
