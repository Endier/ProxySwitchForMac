import CFNetwork
import Foundation
import UserNotifications
import KeyboardShortcuts

let url = URL(fileURLWithPath: "/usr/sbin/networksetup")

@Observable
class SystemProxyStatus {
    var _totalEnable: Bool = true
    
    var totalEnable: Bool {
        get {
            return _totalEnable
        }

        set {
            let serviceNames = ["Wi-Fi", "Ethernet"]
            defaultToggleEnable(serviceNames: serviceNames, bool: newValue)
            _totalEnable = newValue

            // 发送通知
            sentNotifications(isOn: newValue)
        }
    }
    
    init() {
        let networkServices = getSystemNetworkServiceNames()
        let serviceNames = ["Wi-Fi", "Ethernet"]
        let arguments = ["-getwebproxy", "-getsecurewebproxy", "-getsocksfirewallproxy"]
        
        var allDisabled = true
        
        for serviceName in serviceNames {
            if networkServices.contains(serviceName) {
                for argument in arguments {
                    if let proxySetting = getProxySetting(argument: argument, serviceName: serviceName),
                       proxySetting.Enable == "Yes" {
                        allDisabled = false
                        break
                    }
                }
            }
        }
        
        self._totalEnable = !allDisabled
        
        KeyboardShortcuts.onKeyDown(for: .proxySwitch) {
            self.totalEnable.toggle()
        }
    }
}

// 命名并设置默认快捷键
extension KeyboardShortcuts.Name {
    static let proxySwitch = Self("proxySwitch", default: .init(.j, modifiers: .command))
}

class ProxySetting {
    public var Enable: String
    public var Server: String
    public var Port: String

    init(Enable: String, Server: String, Port: String) {
        self.Enable = Enable
        self.Server = Server
        self.Port = Port
    }
}

func getSystemNetworkServiceNames() -> [String] {
    var serviceNames: [String] = []
    // 先创建子线程
    let checkProcess = Process()
    let pipe = Pipe()
    // 在子线程中执行命令
    checkProcess.executableURL = url
    checkProcess.arguments = ["-listallnetworkservices"]
    checkProcess.standardOutput = pipe

    do {
        try checkProcess.run()
    } catch {
        print("Process run error!")
    }

    checkProcess.waitUntilExit()
    var data: Data?

    do {
        data = try pipe.fileHandleForReading.readToEnd()
    } catch {
        print("Read File failed!")
    }

    if let data = data, let output = String(data: data, encoding: .utf8) {
        // 输出的结果是每行都是一个网络服务的名字，所以通过分割字符串来获取所有的网络服务
        // 另外每次执行命令，第一行会固定插入一个说明：带*的服务名处于停用状态，要先把第一行删除
        serviceNames = output.components(separatedBy: .newlines)
            .dropFirst()
            .map { String($0) }
            .filter { !$0.hasPrefix("*") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    #if DEBUG
        print(serviceNames)
    #endif

    return serviceNames
}

func getProxySetting(argument: String, serviceName: String) -> ProxySetting? {
    // 先创建子线程
    let checkProcess = Process()
    checkProcess.executableURL = url
    checkProcess.arguments = [argument, serviceName]

    // Pipe就是类似于channel的东西，用于在不同的进程间传递数据
    // 这里获取开关状态的命令是在子进程执行的，需要把结果传回主进程
    let pipe = Pipe()
    checkProcess.standardOutput = pipe
    do {
        try checkProcess.run()
    } catch {
        print("Failed to run networksetup process: \(error)")
        return nil
    }

    checkProcess.waitUntilExit()

    guard let data = try? pipe.fileHandleForReading.readToEnd() else {
        print("Failed to read process output")
        return nil
    }

    guard let status = String(data: data, encoding: .utf8) else {
        print("Failed to convert data to string")
        return nil
    }

    let errorMessage = "** Error: Unable to find item in network database."

    if status != errorMessage {
        let hashmap = stringToHashMap(string: status)
        let enabled = hashmap["Enabled"] ?? ""
        let server = hashmap["Server"] ?? ""
        let port = hashmap["Port"] ?? ""
        let proxySetting = ProxySetting(
            Enable: enabled,
            Server: server,
            Port: port
        )

        return proxySetting
    }

    return nil
}

func getProxySettings(serviceNames: [String]) -> [ProxySetting] {
    var proxySettingList: [ProxySetting] = []

    let arguments = [
        "-getwebproxy", "-getsecurewebproxy", "-getsocksfirewallproxy",
    ]

    for argument in arguments {
        for serviceName in serviceNames {
            let proxySetting = getProxySetting(argument: argument, serviceName: serviceName)
            if proxySetting != nil {
                proxySettingList.append(proxySetting!)
            }
        }
    }

    return proxySettingList
}

/// 将所有网络服务名输入，逐个获取每个开关的状态，如果有一个关了就返回false，全开才返回true
//func isSwitchOn(proxySettingList: [ProxySetting]) -> Bool {
//    proxySettingList.allSatisfy { $0.Enable == "Yes" }
//}

func toggleEnable(argument: String, serviceName: String, enable: String) {
    let process = Process()
    process.executableURL = url
    process.arguments = [argument, serviceName, enable]
    
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        print("Failed to run networksetup process: \(error)")
    }
}

/// 开关代理不需要很精细，全关或全开即可
public func defaultToggleEnable(serviceNames: [String], bool: Bool) {
    // 在子线程中执行命令
    // 分别是http代理、https代理、SOCKS代理
    let arguments = [
        "-setwebproxystate", "-setsecurewebproxystate",
        "-setsocksfirewallproxystate",
    ]
    // 最后的变量，填写网络络服务的名称，如 "Wi-Fi" 或 "Ethernet"

    let onOrOff: String = bool ? "on" : "off"

    for serviceName in serviceNames {
        for argument in arguments {
            toggleEnable(argument: argument, serviceName: serviceName, enable: onOrOff)
        }
    }
}

func stringToHashMap(string: String) -> [String: String] {
    var hashMap: [String: String] = [:]

    // Swift 这个字符串分割挺好用的
    let lines = string.components(separatedBy: .newlines)

    for line in lines {
        let KV = line.components(separatedBy: ": ")
        if KV.count == 2 {
            hashMap[KV[0]] = KV[1]
        }
    }

    return hashMap
}
