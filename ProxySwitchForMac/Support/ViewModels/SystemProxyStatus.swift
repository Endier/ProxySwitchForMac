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

    /// 最近一次读取到的各服务、各代理类型设置（进程内直读 SCDynamicStore 得到）。
    /// 开启时用于过滤「已配置地址」的代理，决定本次要启用哪些类型；
    /// 同时也被事件驱动（SCDynamicStore）刷新。
    private(set) var cachedSettings: [String: [ProxyType: ProxySetting]] = [:]

    private var toggleTask: Task<Void, Never>?
    private var isToggling = false
    private var configSource: NetworkConfigSource?
    private var refreshDebounceTask: Task<Void, Never>?

    /// 最近一次读取到的主路由服务（当前承载流量的那块网卡）名称，用于开启前校验。
    private var primaryService: String?

    /// 开关结果回调：由外部（App）注入，状态对象本身不直接依赖通知模块，
    /// 只负责在开关完成后把「结果」交出去，便于测试与替换实现。
    var onToggleResult: @MainActor (Bool, Error?) -> Void

    /// 标准初始化：由 App 注入结果处理（如弹通知）的实现。
    init(onToggleResult: @escaping @MainActor (Bool, Error?) -> Void) {
        self.onToggleResult = onToggleResult
        performInitialLoad()
    }

    /// SwiftUI Preview 专用，跳过 networksetup 调用，结果处理为空操作。
    init(previewEnabled: Bool) {
        self.onToggleResult = { _, _ in }
        isProxyOn = previewEnabled
        isLoading = false
    }

    private func performInitialLoad() {
        Task {
            // 先建立配置数据源（含 SCDynamicStore 监听），再读取初始状态，
            // 这样 refreshStatus 可直接复用数据源的同一 store 做进程内读取。
            startObserving()
            await refreshStatus()
            self.isLoading = false
        }
    }

    /// 从系统读取当前代理状态，更新 isProxyOn 与 cachedSettings。
    /// 读路径完全进程内（NetworkConfigSource 直读 SCDynamicStore），不再 fork networksetup 子进程；
    /// 仅「服务名列表」依赖一次 networksetup -listallnetworkservices 调用。
    /// 开关进行中跳过，避免覆盖乐观更新。
    ///
    /// 是否「开启」以**主路由服务**（当前实际承载流量的那块网卡）的代理状态为准，
    /// 而非「任一服务」——这样 UI 反映的才是真实生效的代理。拿不到主服务信息时回退到「任一服务」，保证健壮。
    private func refreshStatus() async {
        guard !isToggling else { return }

        let serviceNames = await NetworkSetupService.fetchActiveServiceNames()
        // 优先复用已建立的数据源（同一 SCDynamicStore）；极端环境下数据源创建失败时，
        // 回退到一次性进程内读取，保证初始状态仍可读（只是失去实时同步）。
        let snapshot = configSource?.read(serviceNames: serviceNames)
            ?? NetworkConfigSource.snapshot(serviceNames: serviceNames)
        cachedSettings = snapshot.settings
        self.primaryService = snapshot.primaryService

        let isEnabled: Bool
        if let primary = snapshot.primaryService, let primarySettings = snapshot.settings[primary] {
            isEnabled = primarySettings.contains { $0.value.isActive }
        } else {
            // 主服务未知（如无 IPv4 连接）：回退到「任一服务有代理即视为开」
            isEnabled = snapshot.settings.contains { $0.value.contains { $0.value.isActive } }
        }
        self.isProxyOn = isEnabled
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
        guard isProxyOn != enabled else { return }

        // 开启前校验：若主服务明确存在却未配置任何代理地址，开启后不会真正生效
        // （UI 仍会因主服务无代理显示「关」），直接提示并中止，避免无意义的系统写入与 UI 抖动。
        // 主服务未知（如临时断网）时不拦截，保留「任一服务」回退行为。
        if enabled,
           let name = primaryService,
           let settings = cachedSettings[name],
           !settings.contains(where: { $0.value.isConfigured })
        {
            onToggleResult(true, ProxyToggleError.primaryServiceNotConfigured(serviceName: name))
            return
        }

        isProxyOn = enabled
        isToggling = true

        toggleTask = Task { [previousTask = toggleTask] in
            _ = await previousTask?.value
            let serviceNames = await NetworkSetupService.fetchActiveServiceNames()

            // 开启时优先用缓存的「已配置信息」，缓存为空（理论不会发生，初始加载已填充）
            // 则回退到 NetworkConfigSource 进程内读取，避免重复 fork 一整轮 networksetup。
            let resolvedConfigured: [String: [ProxyType: Bool]]?
            if enabled {
                resolvedConfigured = cachedSettings.isEmpty
                    ? NetworkConfigSource.snapshot(serviceNames: serviceNames).settings.mapValues { $0.mapValues(\.isConfigured) }
                    : cachedSettings.mapValues { $0.mapValues(\.isConfigured) }
            } else {
                resolvedConfigured = nil
            }

            do {
                try await NetworkSetupService.setAllProxyStates(
                    serviceNames: serviceNames,
                    enabled: enabled,
                    resolvedConfigured: resolvedConfigured
                )
                self.notifyToggleResult(enabled: enabled, error: nil)
            } catch {
                self.isProxyOn = !enabled
                self.notifyToggleResult(enabled: enabled, error: error)
            }
            // 先解除「开关中」标记，再主动刷新一次真实状态：
            // 修正部分服务失败导致的乐观更新偏差，并确保在没有 SCDynamicStore
            // 事件（已移除轮询兜底）时，应用自身操作的结果仍能反映到 UI。
            self.isToggling = false
            await self.refreshStatus()
        }
    }

    /// 将「开关结果」交给注入的回调统一处理（默认实现负责弹通知），
    /// 状态对象不关心通知具体怎么呈现。
    private func notifyToggleResult(enabled: Bool, error: Error?) {
        onToggleResult(enabled, error)
    }
}
