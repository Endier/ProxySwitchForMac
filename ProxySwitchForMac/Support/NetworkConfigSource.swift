//  NetworkConfigSource.swift
//  ProxySwitchForMac
//
//  系统网络配置数据源：单一 SCDynamicStore 既订阅变更、又提供进程内读取，
//  取代原先 ProxyConfigObserver（仅订阅）与 ProxyStateReader（仅读取）各自创建 store 的重复；
//  同时集中了 GUID↔UserDefinedName 解析与主服务判定等共享逻辑。

import Foundation
import SystemConfiguration

/// 一次进程内读取的结果：各服务代理设置 + 当前主路由服务（友好名）。
struct NetworkConfigSnapshot {
    let settings: [String: [ProxyType: ProxySetting]]
    let primaryService: String?
}

/// 基于单一 SCDynamicStore 的网络配置数据源：既监听配置变更、又提供进程内读取。
final class NetworkConfigSource {
    typealias ChangeHandler = () -> Void

    private let store: SCDynamicStore
    private let box: WatcherBox
    private let queue = DispatchQueue(label: "com.proxyswitch.dynamicstore")

    /// 创建并开始监听；若 SCDynamicStore 创建失败（如环境不支持）返回 nil。
    init?(onChange: @escaping ChangeHandler) {
        let box = WatcherBox(onChange: onChange)
        self.box = box

        // 把 box 的所有权交给 CF：passRetained + retain/release 回调，
        // 使 box 生命周期与 store 绑定，避免 store 存续期间回调访问已释放对象。
        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passRetained(box).toOpaque(),
            retain: { info in
                // 回调签名要求返回 const void *（非可选）
                _ = Unmanaged<WatcherBox>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                Unmanaged<WatcherBox>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        guard let store = SCDynamicStoreCreate(
            nil, "ProxySwitchForMac" as CFString, dynamicStoreCallback, &context
        ) else {
            return nil
        }
        self.store = store

        // 只订阅每个服务「偏好(Setup)」下的 Proxies 这一条 pattern：
        // 1) App 镜像的是 Setup 域的每服务 Proxies，这是唯一会被回读的来源；
        // 2) Global 代理 App 不读取，订阅无意义；
        // 3) State 域是「生效中」状态，App 镜像的是偏好(Setup)，与 networksetup -getwebproxy 一致，
        //    且每次开关都会改 Setup，故无需额外订阅 State。
        // 三大代理类型(web/secureWeb/socks)同属一个 Proxies 字典，任一改动只触发该服务一次回调。
        let patterns: [CFString] = [
            "^Setup:/Network/Service/[^/]+/Proxies$" as CFString
        ]
        SCDynamicStoreSetNotificationKeys(store, nil, patterns as CFArray)

        SCDynamicStoreSetDispatchQueue(store, queue)
    }

    /// 停止监听；调用后不会再触发 onChange。
    func stop() {
        SCDynamicStoreSetDispatchQueue(store, nil)
    }

    deinit {
        stop()
    }

    /// 进程内读取指定服务的代理状态与主服务。
    /// 在 store 所在的串行队列上同步执行，与变更回调共用同一队列，避免跨线程访问同一 store。
    func read(serviceNames: [String]) -> NetworkConfigSnapshot {
        queue.sync { [store] in
            Self.snapshot(from: store, serviceNames: serviceNames)
        }
    }

    /// 进程内读取所有指定服务（一次性，自带临时 store，不依赖监听）。
    /// 用于数据源创建失败时的降级，或开关时缓存为空的一次性回读。
    static func snapshot(serviceNames: [String]) -> NetworkConfigSnapshot {
        guard let store = SCDynamicStoreCreate(nil, "ProxySwitchForMac-Reader" as CFString, nil, nil) else {
            return NetworkConfigSnapshot(settings: [:], primaryService: nil)
        }
        return Self.snapshot(from: store, serviceNames: serviceNames)
    }

    /// 直接从 SCDynamicStore 枚举所有网络服务的友好名（UserDefinedName），
    /// 用于 networksetup 失败时的回退，避免依赖猜测的英文名（中文 macOS 上 "以太网" 等会找不到服务导致开关失效）。
    static func fetchAllServiceNames() -> [String] {
        guard let store = SCDynamicStoreCreate(nil, "ProxySwitchForMac-ServiceNames" as CFString, nil, nil) else {
            return []
        }
        let serviceKeys = (SCDynamicStoreCopyKeyList(store, "^Setup:/Network/Service/[^/]+$" as CFString) as? [CFString]) ?? []
        var names: [String] = []
        for key in serviceKeys {
            guard let dict = SCDynamicStoreCopyValue(store, key) as? [String: Any],
                  let name = dict[kSCPropUserDefinedName as String] as? String,
                  !name.isEmpty
            else { continue }
            names.append(name)
        }
        return names
    }

    // MARK: - 共享解析逻辑

    /// 在给定 store 上解析 友好名→GUID 映射，并读取各服务代理状态与主服务。
    private static func snapshot(from store: SCDynamicStore, serviceNames: [String]) -> NetworkConfigSnapshot {
        // 枚举 store 中的服务（按 GUID 为键），建立 友好名 -> GUID 键 的映射。
        let serviceKeys = (SCDynamicStoreCopyKeyList(store, "^Setup:/Network/Service/[^/]+$" as CFString) as? [CFString]) ?? []
        var guidByName: [String: String] = [:]
        for key in serviceKeys {
            guard let dict = SCDynamicStoreCopyValue(store, key) as? [String: Any] else { continue }
            if let name = dict[kSCPropUserDefinedName as String] as? String {
                guidByName[name] = key as String
            }
        }

        // 按传入的友好名列表，读取对应服务的 Proxies 字典并解析。
        var result: [String: [ProxyType: ProxySetting]] = [:]
        for name in serviceNames {
            guard let guidKey = guidByName[name] else { continue }
            let proxiesKey = ((guidKey as String) + "/Proxies") as CFString
            guard let proxies = SCDynamicStoreCopyValue(store, proxiesKey) as? [String: Any] else { continue }
            result[name] = ProxyType.allCases.reduce(into: [:]) { out, type in
                out[type] = Self.parse(proxies, type: type)
            }
        }

        // 主路由服务：State:/Network/Global/IPv4 的 PrimaryService 是服务 GUID，
        // 反查 guidByName 得到友好名。无 IPv4 连接时拿不到，返回 nil。
        var primaryService: String?
        if let ipv4 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
           let primaryGUID = ipv4["PrimaryService"] as? String
        {
            let primaryKey = "Setup:/Network/Service/\(primaryGUID)" as String
            primaryService = guidByName.first(where: { $0.value == primaryKey })?.key
        }

        return NetworkConfigSnapshot(settings: result, primaryService: primaryService)
    }

    /// 从 Proxies 字典解析单个代理类型的设置。键缺失即视为未配置，无需处理 "(null)" 文本。
    private static func parse(_ dict: [String: Any], type: ProxyType) -> ProxySetting {
        let (enableKey, serverKey, portKey) = type.storeKeys
        let enable = (dict[enableKey] as? NSNumber)?.boolValue ?? false
        let server = (dict[serverKey] as? String) ?? ""
        let port: String
        if let num = dict[portKey] as? NSNumber {
            port = String(num.intValue)
        } else if let str = dict[portKey] as? String {
            port = str
        } else {
            port = ""
        }
        return ProxySetting(enable: enable, server: server, port: port)
    }
}

private final class WatcherBox {
    let onChange: NetworkConfigSource.ChangeHandler
    init(onChange: @escaping NetworkConfigSource.ChangeHandler) {
        self.onChange = onChange
    }
}

private let dynamicStoreCallback: SCDynamicStoreCallBack = { _, _, info in
    guard let info else { return }
    Unmanaged<WatcherBox>.fromOpaque(info).takeUnretainedValue().onChange()
}
