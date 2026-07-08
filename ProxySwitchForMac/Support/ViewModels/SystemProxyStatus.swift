//  SystemProxyStatus.swift
//  ProxySwitchForMac
//
//  代理状态的单一数据源（视图模型 / 状态存储）。

import Observation

@MainActor
@Observable
class SystemProxyStatus {
    /// 当前代理是否生效（任一代理已启用即视为开）
    var isProxyOn: Bool = true

    /// 初始状态加载中，UI 应显示加载动画而非实际状态
    private(set) var isLoading = true

    private var toggleTask: Task<Void, Never>?
    private var isToggling = false
    private var configSource: NetworkConfigSource?
    private var refreshDebounceTask: Task<Void, Never>?

    /// 开关结果回调：由外部（App）注入，状态对象本身不直接依赖通知模块，
    /// 只负责在开关完成后把「结果」交出去，便于测试与替换实现。
    /// 第三个参数携带部分失败的明细（整体成功但个别类型未生效），供 App 补提示。
    var onToggleResult: @MainActor (Bool, Error?, NetworkSetupService.ProxyStatesResult?) -> Void

    /// 标准初始化：由 App 注入结果处理（如弹通知）的实现。
    init(onToggleResult: @escaping @MainActor (Bool, Error?, NetworkSetupService.ProxyStatesResult?) -> Void) {
        self.onToggleResult = onToggleResult
        // 同步建立配置数据源（含 SCDynamicStore 监听）：放在 init 而非异步任务里，
        // 确保加载开始前 store 已就绪，refreshStatus 直接复用同一 store 进程内读取、
        // 永不走一次性降级路径。
        startObserving()
        performInitialLoad()
    }

    /// SwiftUI Preview 专用，跳过 networksetup 调用，结果处理为空操作。
    init(previewEnabled: Bool) {
        self.onToggleResult = { _, _, _ in }
        isProxyOn = previewEnabled
        isLoading = false
    }

    private func performInitialLoad() {
        Task {
            await refreshStatus()
            self.isLoading = false
        }
    }

    /// 从系统读取当前代理状态，更新 isProxyOn。
    /// 读路径完全进程内（NetworkConfigSource 直读 SCDynamicStore），零 fork 子进程；
    /// 开关进行中跳过，避免覆盖乐观更新。主服务未知（如暂无 IPv4 连接）时 UI 显示「关」。
    private func refreshStatus() async {
        guard !isToggling else { return }

        // 只读主服务一项，无需枚举其余服务，也不再看其它服务来推断状态。
        guard let primary = readPrimary() else {
            self.isProxyOn = false
            return
        }
        self.isProxyOn = primary.settings.contains { $0.value.isActive }
    }

    /// 只读主路由服务一项（友好名 + 各代理类型设置），用于校验与开启写入。
    /// 走 SCDynamicStore 进程内直读、不 fork 子进程；数据源不可用时降级到一次性读取。
    private func readPrimary() -> (name: String, settings: [ProxyType: ProxySetting])? {
        configSource?.readPrimaryService()
            ?? NetworkConfigSource.primarySnapshot()
    }

    /// 防抖刷新：SCDynamicStore 一次改动会让多个服务的 Proxies key 近乎同时回调，
    /// 若每次都全量重读会做大量重复工作。这里把回调合并：300ms 内再来回调就重置计时，
    /// 仅当「安静」满 300ms 后才真正刷新一次。
    private func scheduleRefresh() {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.refreshStatus()
        }
    }

    /// 启动对系统代理配置的监听：完全依赖事件驱动（SCDynamicStore）。
    /// 本 App 未沙盒化，SCDynamicStore 在常规环境下可用；
    /// 若其创建失败（极端受限环境），则放弃对外部（如系统设置里）改动的实时同步，
    /// 以省去后台轮询的进程开销——自身切换的结果仍会通过 setProxyEnabled 里的
    /// 主动 refreshStatus() 校正，不影响主要用途。
    ///
    /// 注：此处不实现自定义 deinit 来 stop() 监听或 cancel() 任务。
    /// `NetworkConfigSource` 自带 deinit 会调用 `stop()`；
    /// `toggleTask` 总会自行执行完毕并释放对 self 的捕获，不存在永久引用循环。
    /// 该类型由 App 以 `@State` 持有，生命周期等同 App，正常不会析构，
    /// 因此无需在析构路径上强制 `MainActor.assumeIsolated` 而引入崩溃风险。
    private func startObserving() {
        configSource = NetworkConfigSource { [weak self] in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        if configSource == nil {
            // 无事件源：放弃外部变更同步，仅记录日志，避免无意义的后台轮询。
            print("SCDynamicStore 不可用，外部代理变更将不会自动同步")
        }
    }

    /// 开关代理，由 UI Toggle 和快捷键统一调用
    func setProxyEnabled(_ enabled: Bool) {
        // 初始状态加载完成前忽略所有切换请求：此时 isProxyOn 仍是占位初始值、
        // configSource 可能尚未就绪，响应会造成多余的系统写入与非预期通知。
        guard !isLoading else { return }
        guard isProxyOn != enabled else { return }

        // 只读主服务一次：用于开启前的校验，并复用给后续写入（无需二次读取）。
        guard let primary = readPrimary() else {
            onToggleResult(enabled, ProxyToggleError.primaryServiceUnknown, nil)
            return
        }
        let primaryName = primary.name
        let primarySettings = primary.settings

        // 开启前校验：若主服务已存在却未配置任何代理地址，开启后不会真正生效
        // （UI 仍会因主服务无代理显示「关」），直接提示并中止，避免无意义的系统写入与 UI 抖动。
        if enabled,
           !primarySettings.contains(where: { $0.value.isConfigured })
        {
            onToggleResult(enabled, ProxyToggleError.primaryServiceNotConfigured(serviceName: primaryName), nil)
            return
        }

        isProxyOn = enabled
        isToggling = true

        toggleTask = Task { [previousTask = toggleTask] in
            _ = await previousTask?.value

            // 直接复用开关前读到主服务配置，开启时仅启用其已配置地址的代理类型，
            // 避免开启一个没有服务器的代理（无需再次读取系统）。
            let resolvedConfigured: [ProxyType: Bool]? = enabled
                ? primarySettings.mapValues { $0.isConfigured }
                : nil

            do {
                let outcome = try await NetworkSetupService.setProxyStates(
                    serviceName: primaryName,
                    enabled: enabled,
                    resolvedConfigured: resolvedConfigured
                )
                self.notifyToggleResult(enabled: enabled, error: nil, outcome: outcome)
            } catch {
                self.isProxyOn = !enabled
                self.notifyToggleResult(enabled: enabled, error: error, outcome: nil)
            }
            // 先解除「开关中」标记，再主动刷新一次真实状态，
            // 确保在无 SCDynamicStore 事件时，应用自身操作的结果仍能反映到 UI。
            self.isToggling = false
            await self.refreshStatus()
        }
    }

    /// 将「开关结果」交给注入的回调统一处理（默认实现负责弹通知），
    /// 状态对象不关心通知具体怎么呈现。
    private func notifyToggleResult(
        enabled: Bool, error: Error?, outcome: NetworkSetupService.ProxyStatesResult?
    ) {
        onToggleResult(enabled, error, outcome)
    }
}
