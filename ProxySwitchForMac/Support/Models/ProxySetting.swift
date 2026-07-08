//  ProxySetting.swift
//  ProxySwitchForMac
//
//  代理设置的数据模型与代理类型定义。

import Foundation
import SystemConfiguration

/// 单个（服务, 代理类型）的代理设置。
struct ProxySetting {
    let enable: Bool
    let server: String
    let port: String

    /// 是否已真正启用。读路径改走 SCDynamicStore 后，未配置的代理键直接缺失→server 为空串，
    /// 不再出现 networksetup 时代的 "(null)" 文本，故只需判断 enable 与 server 非空。
    var isActive: Bool {
        enable && !server.isEmpty
    }

    /// 是否已配置地址（无论开关是否打开），用于决定开启时是否启用该代理
    var isConfigured: Bool {
        !server.isEmpty
    }
}

/// 代理类型，把「读取参数」与「设置参数」按类型绑定在一起，
/// 取代原先 web/secureWeb/socks 在两条平行数组里靠下标对齐的写法
/// （一旦任一处重排顺序就会错位误开关）。
enum ProxyType: String, CaseIterable {
    case web
    case secureWeb
    case socksFirewall

    var getArgument: String {
        switch self {
        case .web: return "-getwebproxy"
        case .secureWeb: return "-getsecurewebproxy"
        case .socksFirewall: return "-getsocksfirewallproxy"
        }
    }

    var setArgument: String {
        switch self {
        case .web: return "-setwebproxystate"
        case .secureWeb: return "-setsecurewebproxystate"
        case .socksFirewall: return "-setsocksfirewallproxystate"
        }
    }

    /// 用于通知文案与日志的友好名称。
    var displayName: String {
        switch self {
        case .web: return "HTTP"
        case .secureWeb: return "HTTPS"
        case .socksFirewall: return "SOCKS"
        }
    }

    /// 对应 SCDynamicStore 中 Proxies 字典的键名（enable / server / port），
    /// 用于进程内直接读取代理状态，取代 networksetup 文本解析。
    var storeKeys: (enable: String, server: String, port: String) {
        switch self {
        case .web:
            (kSCPropNetProxiesHTTPEnable as String, kSCPropNetProxiesHTTPProxy as String, kSCPropNetProxiesHTTPPort as String)
        case .secureWeb:
            (kSCPropNetProxiesHTTPSEnable as String, kSCPropNetProxiesHTTPSProxy as String, kSCPropNetProxiesHTTPSPort as String)
        case .socksFirewall:
            (kSCPropNetProxiesSOCKSEnable as String, kSCPropNetProxiesSOCKSProxy as String, kSCPropNetProxiesSOCKSPort as String)
        }
    }
}

/// 网络设置相关错误（networksetup 命令执行失败）。
enum NetworkSetupError: LocalizedError {
    case commandFailed(status: Int32, message: String)

    /// 直接暴露 networksetup 的真实报错（stderr），让用户看到确切失败原因，
    /// 而非 Swift 默认的无信息文案。message 为空时回退到通用描述。
    var errorDescription: String? {
        switch self {
        case .commandFailed(_, let message):
            message.isEmpty ? "Network setup command failed." : message
        }
    }
}

/// 开关代理时的「可预期」错误（非系统命令失败），用于向用户给出明确提示。
enum ProxyToggleError: LocalizedError {
    /// 主路由服务未配置任何代理地址：开启后不会真正生效（UI 仍会因主服务无代理显示「关」），
    /// 故拒绝开启并提示用户先在主服务上配置代理。
    case primaryServiceNotConfigured(serviceName: String)
    /// 无法确定主路由服务（如暂无活跃连接）：没有可操作的服务对象，故拒绝切换。
    case primaryServiceUnknown

    var errorDescription: String? {
        switch self {
        case .primaryServiceNotConfigured(let serviceName):
            String(format: String(localized: "PrimaryServiceNoProxy %@"), serviceName)
        case .primaryServiceUnknown:
            String(localized: "PrimaryServiceUnknown")
        }
    }
}
